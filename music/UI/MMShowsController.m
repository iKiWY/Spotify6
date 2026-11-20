#import "MMShowsController.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMTrackListController.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "SpotTheme.h"
#import "MMSongMenu.h"

@interface MMShowsController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMShowsController {
    UITableView *_table;
    UILabel *_hint;
    UIActivityIndicatorView *_spin;
    NSArray *_shows;
    BOOL _loaded;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [SpotTheme styleBackButton:back]; [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
    back.titleLabel.font=[UIFont systemFontOfSize:14]; back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(70,8,W-140,34)]; nav.text=L(@"Podcasts");
    nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorColor=[SpotTheme line];
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=60;
    _table.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(84),0);
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [SpotTheme skinTable:_table]; [self.view addSubview:_table];
    __weak MMShowsController*weakSelf=self;
    [MMSongMenu attachToTable:_table swipeToQueue:NO trackAt:^NSDictionary*(NSIndexPath*ip){
        MMShowsController*strongSelf=weakSelf;
        if(!strongSelf || ip.row<0 || ip.row>=(NSInteger)strongSelf->_shows.count) return nil;
        NSDictionary*row=strongSelf->_shows[ip.row]; NSMutableDictionary*episode=[row mutableCopy];
        episode[@"title"]=row[@"name"]?:L(@"Episode"); episode[@"artist"]=row[@"publisher"]?:L(@"Podcast"); episode[@"mediaType"]=@"episode";
        return episode;
    }];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,120,W-40,72)]; _hint.numberOfLines=0;
    _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.hidden=YES;
    [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(W/2,230); _spin.hidesWhenStopped=YES; [self.view addSubview:_spin];
    MMAutoMask(self.view);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if(_loaded) return;
    _loaded=YES;
    if(![MMSpotify hasUserToken]){ _hint.text=L(@"Please log in again."); _hint.hidden=NO; return; }
    _hint.text=L(@"Loading your podcasts …"); _hint.hidden=NO; [_spin startAnimating];
    [MMSpotify latestPodcastEpisodes:^(NSArray*items,NSInteger st){
        [_spin stopAnimating];
        if(![items isKindOfClass:[NSArray class]]){
            _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load."); _hint.hidden=NO; return;
        }
        NSMutableArray*out=[NSMutableArray array];
        for(id item in items){
            if(![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary*show=[item[@"show"] isKindOfClass:[NSDictionary class]]?item[@"show"]:@{};
            if(![item[@"id"] isKindOfClass:[NSString class]]) continue;
            [out addObject:@{@"id":item[@"id"],@"name":[item[@"name"] isKindOfClass:[NSString class]]?item[@"name"]:L(@"Episode"),
                             @"publisher":[show[@"name"] isKindOfClass:[NSString class]]?show[@"name"]:L(@"Podcast"),
                             @"cover":[MMCovers smallURL:item[@"images"]]?:[MMCovers smallURL:show[@"images"]]?:@"",
                             @"release_date":[item[@"release_date"] isKindOfClass:[NSString class]]?item[@"release_date"]:@""}];
        }
        _shows=out; _hint.hidden=(out.count>0);
        if(!out.count) _hint.text=L(@"No saved podcasts yet.");
        [_table reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _shows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell*c=[tableView dequeueReusableCellWithIdentifier:MMCellID(@"show",tableView)];
    if(!c){
        c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"show",tableView)];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleBlue;
        UIImageView*cover=[[UIImageView alloc] initWithFrame:[SpotTheme ios6]?CGRectMake(0,0,44,44):CGRectMake(6,6,48,48)];
        cover.tag=10; cover.contentMode=UIViewContentModeScaleAspectFill; cover.clipsToBounds=YES; [c.contentView addSubview:cover];
        UILabel*title=[[UILabel alloc] initWithFrame:CGRectMake([SpotTheme ios6]?53:62,2,tableView.bounds.size.width-([SpotTheme ios6]?92:102),36)];
        title.tag=11; title.font=[UIFont boldSystemFontOfSize:15]; title.textColor=[SpotTheme ink]; title.numberOfLines=2; title.lineBreakMode=NSLineBreakByTruncatingTail; [c.contentView addSubview:title];
        UILabel*publisher=[[UILabel alloc] initWithFrame:CGRectMake([SpotTheme ios6]?53:62,39,tableView.bounds.size.width-([SpotTheme ios6]?92:102),17)];
        publisher.tag=12; publisher.font=[UIFont systemFontOfSize:12]; publisher.textColor=[SpotTheme faint]; publisher.lineBreakMode=NSLineBreakByTruncatingTail; [c.contentView addSubview:publisher];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary*show=_shows[indexPath.row]; UIImageView*cover=(UIImageView*)[c.contentView viewWithTag:10];
    UILabel*title=(UILabel*)[c.contentView viewWithTag:11]; UILabel*publisher=(UILabel*)[c.contentView viewWithTag:12];
    CGFloat W=tableView.bounds.size.width;
    title.frame=CGRectMake([SpotTheme ios6]?53:62,2,W-([SpotTheme ios6]?92:102),36);
    publisher.frame=CGRectMake([SpotTheme ios6]?53:62,39,W-([SpotTheme ios6]?92:102),17);
    title.text=show[@"name"]; publisher.text=show[@"publisher"];
    [MMCovers playlistPlaceholderInto:cover]; cover.backgroundColor=[SpotTheme card];
    NSString*url=show[@"cover"];
    if(url.length) [MMCovers thumb:url size:48 radius:0 into:cover];
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary*episode=_shows[indexPath.row];
    [[MMRootController shared] playTrackId:episode[@"id"] title:episode[@"name"] artist:episode[@"publisher"] cover:episode[@"cover"] mediaType:@"episode"];
}

- (void)close { [[MMRootController shared] popContent]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }

@end
