import Foundation

nonisolated struct YouTubeClip: Equatable, Sendable {
    let videoID: String
    init?(videoID: String) {
        guard videoID.utf8.count == 11, videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        self.videoID = videoID
    }
    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=" + videoID)! }
}

nonisolated enum YouTubeEmbedDocument {
    // YouTube requires the app identity as Referer for locally hosted WebViews.
    // This is the bundle identity, not an invented website endpoint.
    static let origin = URL(string: "https://org.stationcat.music")!
    static func html(_ clip: YouTubeClip, token: String) -> String {
        // Only a validated 11-character ID and an internally generated UUID
        // enter this document. Titles, URLs, UTM data and lyrics never enter JS.
        guard UUID(uuidString: token) != nil else { return "" }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(token)' https://www.youtube.com; frame-src https://www.youtube-nocookie.com; style-src 'unsafe-inline'; base-uri 'none'">
        <style>html,body,#player{margin:0;width:100%;height:100%;background:#060a16;overflow:hidden}</style>
        </head><body><div id="player"></div>
        <script nonce="\(token)">
        let player;
        function report(event,code){window.webkit.messageHandlers.youtube.postMessage({token:'\(token)',event:event,code:code||0});}
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{
          host:'https://www.youtube-nocookie.com',width:'100%',height:'100%',videoId:'\(clip.videoID)',
          playerVars:{autoplay:0,playsinline:1,controls:1,rel:0,origin:'\(origin.absoluteString)'},
          events:{onReady:function(){report('ready');},onError:function(e){report('error',e.data);}}
        });}
        function stopClip(){if(player){player.destroy();player=null;}}
        window.addEventListener('pagehide',stopClip);
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
    }
}
