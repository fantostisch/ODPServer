# Development resources

* [WebSocket library](https://github.com/jaspervdj/websockets)
* [WebSocket library documentation](https://jaspervdj.be/websockets/index.html)
* [WAI: Web Application Interface](https://www.yesodweb.com/book/web-application-interface)
* [WAI WebSockets example](https://github.com/yesodweb/wai/blob/master/wai-websockets/server.lhs)
* [Deploying your Webapp](https://www.yesodweb.com/book/deploying-your-webapp)
* [Warp](http://www.aosabook.org/en/posa/warp.html)

# Unanswered questions

## How are wsTag and wsClient generated?

We can not use wsTag and wsClient as unique identifier, because they do not seem to differ when
using another browser on the same device.
