#!/usr/bin/env python3
"""Exercise production podcast endpoint and quality selection helpers via GNUstep."""
from pathlib import Path
import shlex
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
source = Path(os.environ.get("MMSPOTIFY_SOURCE_OVERRIDE", root / "music/Spot/MMSpotify.m")).read_text()
api_user_start = source.index("+ (void)apiUser:(NSString *)method path:")
api_user_end = source.index("// Stale-while-revalidate", api_user_start)
api_user_implementation = source[api_user_start:api_user_end]
if "usesWebAPIForUserGET(path)" not in api_user_implementation or "webAPIPathForUserGET(path)" not in api_user_implementation:
    raise SystemExit("show and search requests must route through the developer Web API token")
saved_shows_impl = source[source.index("+ (void)savedShows:"):source.index("// ---- Login mit Code", source.index("+ (void)savedShows:"))]
if 'spSavedShowIds(&st)' not in saved_shows_impl or 'shows?ids=%@' not in saved_shows_impl:
    raise SystemExit("saved podcasts must come from the internal account collection and resolve public show metadata")
if 'show metadata batch unavailable HTTP %ld; keeping IDs' not in saved_shows_impl:
    raise SystemExit("a forbidden bulk show lookup must not discard saved show IDs")
if '+ (void)latestPodcastEpisodes:' not in saved_shows_impl or 'spEpisodeIdsInSet(setName,user,&st)' not in saved_shows_impl:
    raise SystemExit("Podcasts Library must read the user's saved episode collection")
if 'NSArray*recentIds=ids.count>50?[ids subarrayWithRange:NSMakeRange(0,50)]:ids;' not in saved_shows_impl or 'spEpisodes(recentIds,&metadataStatus)' not in saved_shows_impl:
    raise SystemExit("the latest saved episode feed must resolve only its newest 50 entries")
if 'spExt(uris,12,status)' not in source or 'episodes?ids=%@' in saved_shows_impl or 'apiUserAllItems:path' in saved_shows_impl:
    raise SystemExit("saved episode IDs must resolve through internal EpisodeV4 metadata, not the forbidden public endpoint")
episode_metadata = source[source.index("static NSArray* spEpisodes"):source.index("// Album-Protobuf", source.index("static NSArray* spEpisodes"))]
for field in ('psub(ep,2)', 'psub(ep,71)', 'psub(ep,68)', 'psub(show,69)', 'pvarval(ep,7)'):
    if field not in episode_metadata:
        raise SystemExit(f"EpisodeV4 metadata mapping is missing {field}")
if 'smallCoverFromGroup' not in episode_metadata or 'pvarval(im,2); if(size==1)' not in source:
    raise SystemExit("podcast rows must use Spotify's small artwork variant")
if 'resolved saved podcast episodes -> HTTP %d (%lu episodes)' not in saved_shows_impl or 'metadataStatus=502' not in saved_shows_impl:
    raise SystemExit("metadata lookup failures must complete with an error instead of an endless loading state")
if '@[@"episode",@"episodes",@"listenlater"]' not in saved_shows_impl:
    raise SystemExit("saved episode lookup must probe Spotify episode collection sets")
if 'spotify:show:' not in source[source.index("static NSArray* spShowIdsInSet"):source.index("static NSDictionary* trackPage")]:
    raise SystemExit("saved show collection parsing must retain spotify:show URIs")
if 'spotify:episode:' not in source[source.index("static NSArray* spEpisodeIdsInSet"):source.index("// Saved tracks use")]:
    raise SystemExit("saved episode collection parsing must retain spotify:episode URIs")
if '@[@"show",@"shows",@"podcast",@"podcasts",@"collection"]' not in source:
    raise SystemExit("saved show lookup must probe the internal podcast collection sets")
shows_controller = (root / "music/UI/MMShowsController.m").read_text()
if '[MMSpotify latestPodcastEpisodes:' not in shows_controller or 'me/shows?limit=50' in shows_controller:
    raise SystemExit("Podcasts Library must show aggregated recent episodes, not call the rate-limited me/shows route")
if 'attachToTable:_table swipeToQueue:NO trackAt:' not in shows_controller or 'episode[@"mediaType"]=@"episode"' not in shows_controller:
    raise SystemExit("podcast episodes must expose the long-press context menu with their media type")
song_menu = (root / "music/UI/MMSongMenu.m").read_text()
if 'showForEpisode:' not in song_menu or 'queueDownloadEpisodes:@[eid]' not in song_menu or 'deleteDownload:[@"episode:" stringByAppendingString:eid]' not in song_menu:
    raise SystemExit("episode context actions must play/queue and download/remove episodes")
metadata_start = source.index("static NSString* metadataURIForMediaType")
metadata_end = source.index("\n}", metadata_start) + 2
quality_start = source.index("static NSInteger preferredBitrateForMediaType")
quality_end = source.index("\n}", quality_start) + 2
download_quality_start = source.index("static NSInteger preferredDownloadBitrateForMediaType")
download_quality_end = source.index("\n}", download_quality_start) + 2
queue_start = source.index("static BOOL isEpisodeQueueID")
queue_end = source.index("static NSString* diskPath", queue_start)
offline_start = source.index("static NSData* offlineMediaData")
offline_end = source.index("\n}", offline_start) + 2
web_api_start = source.index("static BOOL usesWebAPIForUserGET")
web_api_end = source.index("\n}", web_api_start) + 2
web_path_start = source.index("static NSString* webAPIPathForUserGET")
web_path_end = source.index("\n}", web_path_start) + 2
parser_start = source.index("static uint64_t rvar")
parser_end = source.index("static int rd_all", parser_start)
psubs_start = source.index("static NSArray* psubs")
psubs_end = source.index("// 16-Byte gid", psubs_start)
helpers = source[parser_start:parser_end] + "\n" + source[psubs_start:psubs_end] + "\n" + source[metadata_start:metadata_end] + "\n" + source[quality_start:quality_end] + "\n" + source[download_quality_start:download_quality_end] + "\n" + source[queue_start:queue_end] + "\n" + source[offline_start:offline_end] + "\n" + source[web_api_start:web_api_end] + "\n" + source[web_path_start:web_path_end]
harness = r'''
#import <Foundation/Foundation.h>
#import "MMMediaQuality.h"
static NSString *gCountry = @"BR";
@implementation MMMediaQuality
+ (NSInteger)streamingBitrateForCurrentNetwork { return 96; }
+ (NSInteger)podcastStreamingBitrateForCurrentNetwork { return 320; }
+ (NSInteger)downloadBitrateForCurrentNetwork { return 160; }
+ (NSInteger)podcastDownloadBitrateForCurrentNetwork { return 96; }
@end
HELPERS
static void check(NSString *name, BOOL condition) { NSCAssert(condition,@"%@",name); printf("PASS %s\n",[name UTF8String]); }
int main(void) { NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    check(@"track metadata endpoint stays track", [[metadataURIForMediaType(@"track",@"abc") description] isEqual:@"hm://metadata/4/track/abc"]);
    check(@"episode metadata endpoint uses episode type", [[metadataURIForMediaType(@"episode",@"def") description] isEqual:@"hm://metadata/4/episode/def"]);
    check(@"unknown media type is rejected", metadataURIForMediaType(@"show",@"abc")==nil);
    check(@"track keeps music streaming quality", preferredBitrateForMediaType(@"track")==96);
    check(@"episode uses podcast streaming quality", preferredBitrateForMediaType(@"episode")==320);
    check(@"unknown media type has no quality", preferredBitrateForMediaType(@"show")==0);
    check(@"track download uses music quality", preferredDownloadBitrateForMediaType(@"track")==160);
    check(@"episode download uses podcast quality", preferredDownloadBitrateForMediaType(@"episode")==96);
    check(@"unknown media type has no download quality", preferredDownloadBitrateForMediaType(@"show")==0);
    unsigned char malformedBytes[]={0x0a,0x05,0x01}; NSData *malformed=[NSData dataWithBytes:malformedBytes length:sizeof(malformedBytes)];
    check(@"truncated protobuf byte fields are rejected safely", psub(malformed,1)==nil && [psubs(malformed,1) count]==0);
    check(@"truncated protobuf varint fields are rejected safely", pvarval(malformed,2)==-1);
    check(@"show episode lists use the developer Web API token", usesWebAPIForUserGET(@"shows/show-id/episodes?market=from_token"));
    check(@"search keeps its existing developer Web API route", usesWebAPIForUserGET(@"search?q=show&type=show"));
    check(@"ordinary account endpoints keep their user token route", !usesWebAPIForUserGET(@"me/tracks?limit=50"));
    check(@"show episode list uses the account market", [webAPIPathForUserGET(@"shows/show-id/episodes?market=from_token") isEqual:@"shows/show-id/episodes?market=BR"]);
    check(@"episode queue IDs retain media type", [queueIDForMedia(@"abc",@"episode") isEqual:@"episode:abc"] && isEpisodeQueueID(@"episode:abc") && [mediaIDFromQueueID(@"episode:abc") isEqual:@"abc"] && [mediaTypeFromQueueID(@"episode:abc") isEqual:@"episode"]);
    NSString *offlinePath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"spotify6-podcast-offline-fixture.ogg"];
    NSData *payload=[@"mapped offline podcast" dataUsingEncoding:NSUTF8StringEncoding]; [payload writeToFile:offlinePath atomically:YES];
    check(@"offline episodes are read from the file-backed data path", [offlineMediaData(offlinePath,@"episode") isEqualToData:payload]);
    check(@"offline music keeps its existing data path", [offlineMediaData(offlinePath,@"track") isEqualToData:payload]);
    [[NSFileManager defaultManager] removeItemAtPath:offlinePath error:NULL];
    [pool drain]; return 0;
}
'''.replace("HELPERS", helpers)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-playback-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-Wno-incomplete-implementation", "-I", str(root / "music/Spot"), "-I", objc_include,
                    str(path / "test.m"), "-o", str(path / "test"), *libs], check=True)
    subprocess.run([str(path / "test")], check=True)
