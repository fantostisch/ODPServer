# Development resources

* [WebScoket library](https://github.com/jaspervdj/websockets)
* [Websocket library documentation](https://jaspervdj.be/websockets/index.html)
* [WAI: Web Application Interface](https://www.yesodweb.com/book/web-application-interface)
* [WAI Websockets example](https://github.com/yesodweb/wai/blob/master/wai-websockets/server.lhs)
* [Deploying your Webapp](https://www.yesodweb.com/book/deploying-your-webapp)
* [Warp](http://www.aosabook.org/en/posa/warp.html)

# Unanswered questions

## How are wsTag and wsClient generated?

We can not use wsTag and wsClient as unique identifier, because they do not seem to differ when
using another browser on the same device.

## What do the 4 characters before every websocket message mean?

For example:

```
"000f{\"func\":\"ping\"}"
"000f{\"func\":\"pong\"}"
```
