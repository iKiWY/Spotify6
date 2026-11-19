#import "MMMediaQualityController.h"
#import "MMMediaQuality.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMLayout.h"
#import "SpotTheme.h"
#import "MMSheet.h"
#import "MeshL10n.h"

@interface MMMediaQualityController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMMediaQualityController {
    UITableView *_table;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme pageBackground];
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    UIButton *back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [back setTitle:L(@"Back") forState:UIControlStateNormal]; [SpotTheme styleBackButton:back];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(90,8,w-180,34)]; title.text=L(@"Media Quality");
    title.font=[UIFont boldSystemFontOfSize:16]; title.textAlignment=NSTextAlignmentCenter;
    title.textColor=[SpotTheme ink]; title.backgroundColor=[UIColor clearColor]; [self.view addSubview:title];
    CGFloat bottomInset=MMIsPad()?0:[[MMRootController shared] bottomBarsHeight];
    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,w,MAX(0,h-46-bottomInset)) style:UITableViewStyleGrouped];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=[SpotTheme ios6]?UITableViewCellSeparatorStyleSingleLine:UITableViewCellSeparatorStyleNone;
    if([SpotTheme ios6]){ _table.backgroundView=nil; _table.backgroundColor=[UIColor clearColor]; }
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=40;
    _table.scrollEnabled=NO; _table.bounces=NO;
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_table];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat bottomInset=MMIsPad()?0:[[MMRootController shared] bottomBarsHeight];
    _table.frame=CGRectMake(0,46,self.view.bounds.size.width,MAX(0,self.view.bounds.size.height-46-bottomInset));
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 26; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 0.01; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section==0?L(@"Streaming"):L(@"Downloads");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    BOOL wifi=indexPath.row==0;
    cell.textLabel.text=wifi?L(@"Wi-Fi"):L(@"Mobile Data");
    NSInteger bitrate=0;
    if(indexPath.section==0) bitrate=wifi?[MMMediaQuality streamingBitrateForWiFi]:[MMMediaQuality streamingBitrateForMobile];
    else bitrate=wifi?[MMMediaQuality downloadBitrateForWiFi]:[MMMediaQuality downloadBitrateForMobile];
    cell.detailTextLabel.text=[MMMediaQuality labelForBitrate:bitrate];
    cell.textLabel.textColor=[SpotTheme ink]; cell.detailTextLabel.textColor=[SpotTheme muted];
    cell.backgroundColor=[SpotTheme card]; cell.selectionStyle=UITableViewCellSelectionStyleGray;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL wifi=indexPath.row==0, streaming=indexPath.section==0;
    NSArray *options=streaming?@[@"96 kbps",@"160 kbps",@"320 kbps"]:(wifi?@[@"96 kbps",@"160 kbps",@"320 kbps"]:@[@"Off",@"96 kbps",@"160 kbps",@"320 kbps"]);
    NSInteger current=streaming?(wifi?[MMMediaQuality streamingBitrateForWiFi]:[MMMediaQuality streamingBitrateForMobile]):(wifi?[MMMediaQuality downloadBitrateForWiFi]:[MMMediaQuality downloadBitrateForMobile]);
    NSInteger selected=0; for(NSUInteger i=0;i<options.count;i++) if([options[i] hasPrefix:[MMMediaQuality labelForBitrate:current]]) selected=(NSInteger)i;
    NSMutableArray *marked=[NSMutableArray arrayWithArray:options];
    marked[selected]=[NSString stringWithFormat:@"✓  %@",marked[selected]];
    NSString *heading=streaming?(wifi?L(@"Wi-Fi Streaming"):L(@"Mobile Streaming")):(wifi?L(@"Wi-Fi Downloads"):L(@"Mobile Downloads"));
    [MMSheet showIn:[MMRootController shared].view title:heading subtitle:nil options:marked done:^(NSInteger index){
        if(index<0||index>=(NSInteger)options.count) return;
        NSInteger value=[options[index] isEqualToString:@"Off"]?0:[[options[index] componentsSeparatedByString:@" "][0] integerValue];
        if(streaming) [MMMediaQuality setStreamingBitrate:value forWiFi:wifi]; else [MMMediaQuality setDownloadBitrate:value forWiFi:wifi];
        [self->_table reloadData];
    }];
}
- (void)close { [[MMRootController shared] popContent]; }
@end
