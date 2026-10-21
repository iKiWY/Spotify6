#import "MMDownloadsController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMTrackListController.h"
#import "MMCovers.h"
#import "MeshL10n.h"

@interface MMDownloadsController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMDownloadsController {
    UITableView *_table;
    UILabel *_hint;
    NSDictionary *_status;          // MMSpotify downloadStatus
    NSArray *_done;                 // @[ {id, bytes, date} ]
    long long _doneBytes;
    NSMutableDictionary *_info;     // id -> {title, artist, cover}
    NSMutableSet *_asked;           // schon übers Netz angefragte IDs
    BOOL _knownLoaded;              // gespeicherte Listen gelesen (erst danach übers Netz nachfragen)
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [SpotTheme styleBackButton:back]; back.titleLabel.font=[UIFont systemFontOfSize:14];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(90,8,W-180,34)]; nav.text=L(@"Downloads"); nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.backgroundColor=[UIColor clearColor]; [self.view addSubview:nav];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorColor=[SpotTheme line]; _table.rowHeight=60;
    _table.dataSource=self; _table.delegate=self; _table.contentInset=_table.scrollIndicatorInsets=UIEdgeInsetsMake(0,0,MMPageBottomInset(90),0);
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [SpotTheme skinTable:_table]; if([SpotTheme ios6]) _table.allowsSelection=NO; [self.view addSubview:_table];   // Zeilen haben keine Tipp-Aktion

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,140,W-40,40)]; _hint.text=L(@"No downloaded songs yet."); _hint.textColor=[SpotTheme faint];
    _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.backgroundColor=[UIColor clearColor]; _hint.hidden=YES; [self.view addSubview:_hint];

    _info=[NSMutableDictionary dictionary]; _asked=[NSMutableSet set];
    for(NSString*n in @[@"MMDownloadProgress",@"MMDownloadDone",@"MMDownloadsChanged"])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:n object:nil];
    [self reload];
    [self loadKnownInfo];
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)close { [[MMRootController shared] popContent]; }

- (void)reload {
    _status=[MMSpotify downloadStatus];
    _done=[MMSpotify downloadedTracks]; _doneBytes=0; for(NSDictionary*d in _done) _doneBytes+=[d[@"bytes"] longLongValue];
    _hint.hidden=(_done.count || [self queue].count);
    [_table reloadData];
    [self fetchMissingInfo];
}
- (NSArray *)queue { return [MMSpotify isDownloading]?_status[@"queue"]:@[]; }

// Titel/Artist/Cover: erst aus den gespeicherten Listen (geht offline), was fehlt übers Netz
- (void)loadKnownInfo {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{ @autoreleasepool {
        NSString*dir=MMPath(@".spotcache");
        NSMutableDictionary*by=[[NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"dlinfo.plist"]] mutableCopy]?:[NSMutableDictionary dictionary];   // beim Herunterladen gemerkt
        for(NSString*k in [by allKeys]) if(![by[k][@"title"] length] || [by[k][@"title"] isEqualToString:@"…"]) [by removeObjectForKey:k];
        for(NSString*f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]){
            if(![f hasPrefix:@"list_"] || ![f hasSuffix:@".plist"]) continue;
            for(NSDictionary*t in [NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:f]]){
                if(![t isKindOfClass:[NSDictionary class]] || ![t[@"id"] isKindOfClass:[NSString class]] || ![t[@"title"] length] || [t[@"title"] isEqualToString:@"…"]) continue;   // "…" = Platzhalter, kein Titel
                by[t[@"id"]]=@{@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""};
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [_info addEntriesFromDictionary:by]; _knownLoaded=YES; [_table reloadData]; [self fetchMissingInfo]; });
    }});
}
- (void)fetchMissingInfo {
    if(!_knownLoaded) return;   // erst die gespeicherten Listen abwarten
    if(![MMSpotify networkReachable]) return;
    NSMutableArray*miss=[NSMutableArray array];
    for(NSString*tid in [[_done valueForKey:@"id"] arrayByAddingObjectsFromArray:[self queue]])
        if(!_info[tid] && ![_asked containsObject:tid]){ [miss addObject:tid]; [_asked addObject:tid]; if(miss.count>=100) break; }
    if(!miss.count) return;
    [MMSpotify trackInfos:miss completion:^(NSDictionary*by){ [_info addEntriesFromDictionary:by]; [_table reloadData]; }];
}

static NSString* fmtEta(double s){
    if(s<0) return nil;
    if(s<90) return L(@"less than 2 min left");
    long m=(long)((s+30)/60); if(m<60) return LF(@"about %ld min left",m);
    return LF(@"about %ld h %ld min left",m/60,m%60);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if(s==0){ NSInteger q=[self queue].count; return q?1+MIN(q,(NSInteger)50):0; }   // Fortschrittszeile + die nächsten 50
    return _done.count;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return [self tableView:tv numberOfRowsInSection:s]?([SpotTheme ios6]?22:36):0; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if([SpotTheme ios6]) return [SpotTheme plainSectionHeader:s==0?L(@"Downloading"):LF(@"Downloaded · %lu songs · %@",(unsigned long)_done.count,[MMTrackListController fmtBytes:_doneBytes]) width:tv.bounds.size.width];
    UIView*v=[[UIView alloc] initWithFrame:CGRectMake(0,0,tv.bounds.size.width,36)]; v.backgroundColor=[SpotTheme bg];
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,10,tv.bounds.size.width-32,22)]; l.backgroundColor=[UIColor clearColor];
    l.font=[UIFont boldSystemFontOfSize:17]; l.textColor=[SpotTheme ink];
    l.text=s==0?L(@"Downloading"):LF(@"Downloaded · %lu songs · %@",(unsigned long)_done.count,[MMTrackListController fmtBytes:_doneBytes]);
    l.adjustsFontSizeToFitWidth=YES; [v addSubview:l]; return v;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    if(ip.section==0 && ip.row==0){   // Fortschritt
        UITableViewCell*c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        NSInteger d=[_status[@"done"] integerValue], t=[_status[@"total"] integerValue];
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,10,W-32,20)]; l.backgroundColor=[UIColor clearColor]; l.font=[UIFont systemFontOfSize:14]; l.textColor=[SpotTheme muted];
        NSString*eta=fmtEta([_status[@"eta"] doubleValue]);
        l.text=eta?LF(@"%ld of %ld songs · %@",(long)d,(long)t,eta):LF(@"%ld of %ld songs",(long)d,(long)t); [c.contentView addSubview:l];
        UIProgressView*p=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; p.frame=CGRectMake(16,40,W-32,9);
        p.progressTintColor=[SpotTheme green]; p.trackTintColor=[SpotTheme card]; p.progress=t?(float)d/t:0; [c.contentView addSubview:p];
        return c;
    }
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"s",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"s",tv)]; c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,8,44,44)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.contentMode=UIViewContentModeScaleAspectFill; cov.clipsToBounds=YES; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(72,11,W-72-70,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; ti.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(72,31,W-72-70,18)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; ar.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:ar];
        UILabel*sz=[[UILabel alloc] initWithFrame:CGRectMake(W-66,0,52,60)]; sz.tag=4; sz.font=[UIFont systemFontOfSize:12]; sz.textColor=[SpotTheme faint]; sz.textAlignment=NSTextAlignmentRight; sz.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:sz];
        UIActivityIndicatorView*sp=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; sp.tag=5; sp.center=CGPointMake(W-30,30); [c.contentView addSubview:sp]; }
    NSString*tid; NSString*size=@""; BOOL now=NO;
    if(ip.section==0){ tid=[self queue][ip.row-1]; now=(ip.row==1); }
    else { NSDictionary*d=_done[ip.row]; tid=d[@"id"]; size=[MMTrackListController fmtBytes:[d[@"bytes"] longLongValue]]; }
    NSDictionary*in=_info[tid];
    ((UILabel*)[c.contentView viewWithTag:2]).text=[in[@"title"] length]?in[@"title"]:L(@"Loading …");
    ((UILabel*)[c.contentView viewWithTag:3]).text=ip.section==0?(now?L(@"Downloading now"):L(@"Waiting")):(in[@"artist"]?:@"");
    ((UILabel*)[c.contentView viewWithTag:4]).text=size;
    UIActivityIndicatorView*sp=(UIActivityIndicatorView*)[c.contentView viewWithTag:5]; if(now)[sp startAnimating]; else [sp stopAnimating];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1]; cov.image=nil;
    if([in[@"cover"] length]) [MMCovers thumb:in[@"cover"] size:44 radius:0 into:cov];
    return c;
}
// Nach links wischen: heruntergeladenen Song löschen
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return ip.section==1; }
- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return L(@"Delete"); }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if(st!=UITableViewCellEditingStyleDelete || ip.section!=1 || ip.row>=(NSInteger)_done.count) return;
    NSDictionary*d=_done[ip.row];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"MMDownloadsChanged" object:nil];   // eigene Löschung nicht doppelt neu laden
    [MMSpotify deleteDownload:d[@"id"]];
    NSMutableArray*m=[_done mutableCopy]; [m removeObjectAtIndex:ip.row]; _done=m; _doneBytes-=[d[@"bytes"] longLongValue];
    [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationLeft];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [_table reloadData]; });   // Kopfzeile: Anzahl + Größe
    _hint.hidden=(_done.count || [self queue].count);
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:@"MMDownloadsChanged" object:nil]; });
}
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
