package whet.stones;

class HtmlStone extends whet.Whetstone {
    
    public var config:HtmlConfig;
    
    public function new(project:WhetProject, config:HtmlConfig = null) {
        super(project);
        this.config = config == null ? { } : config;
        if(this.config.title == null) this.config.title = project.config.name;
        if(this.config.description == null) this.config.description = project.config.description;
        //TODO:
        //x config options for common elements
        //x build by iterating the config and use string builder
        // save command, ability to use from ServerStone
        // figure out some way to get data from other Stones, one way or another
        // e.g. stylesheet could be Asset ref, and AssetsStone would give the path based on config, or something (don't overthink it)
    }
    
    public function addBodyScript(src:String):Void {
        config.bodyElements.push('<script type="text/javascript" src="$src"></script>');
    }
    
    public function getContent():String {
        var sb = new StringBuf();
        sb.add('<!DOCTYPE html>\n');
        sb.add('<html lang="en">\n');
        sb.add('<head>\n');
        sb.add('\t<meta charset="utf-8"/>\n');
        if(config.title != null && config.title != "") {
            sb.add('\t<title>${config.title}</title>\n');
            sb.add('\t<meta property="og:title" content="${config.title}">\n');
        }
        if(config.noScaleMeta)
            sb.add('\t<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no">\n');
        if(config.stylePaths != null) for(path in config.stylePaths)
            sb.add('\t<link rel="stylesheet" href="$path">\n');
        if(config.description != null && config.description != "") {
            sb.add('\t<meta name="description" content="${config.description}">\n');
            sb.add('\t<meta property="og:description" content="${config.description}">\n');
        }
        if(config.keywords != null && config.keywords.length > 0) {
            sb.add('\t<meta name="keywords" content="${config.keywords.join(",")}">\n');
        }
        if(config.ogUrl != null && config.ogUrl != "")
            sb.add('\t<meta property="og:url" content="${config.ogUrl}">\n');
        if(config.ogImage != null) {
            var img = config.ogImage;
            sb.add('\t<meta property="og:image" content="${img.image}">\n');
            sb.add('\t<meta property="og:image:type" content="${img.type}" />\n');
            sb.add('\t<meta property="og:image:width" content="${img.width}">\n');
            sb.add('\t<meta property="og:image:height" content="${img.height}">\n');
        }
        if(config.ogType != null)
            sb.add('\t<meta property="og:type" content="${config.ogType}">\n');
        for(el in config.headElements)
            sb.add(el.split('\n').map(line -> '\t$line').join('\n'));
        sb.add('</head>');
        sb.add('<body>');
        
        for(el in config.bodyElements)
            sb.add(el.split('\n').map(line -> '\t$line').join('\n'));
        sb.add('</body>');
        sb.add('</html>');
        return sb.toString();
    }
    
}

@:structInit class HtmlConfig {
    
    public var headElements:Array<String> = [];
    public var bodyElements:Array<String> = [];
    public var noScaleMeta:Bool = true;
    public var stylePaths:Array<String> = null;
    public var title:String = null;
    public var description:String = null;
    public var keywords:Array<String> = null;
    public var ogUrl:String = null;
    public var ogImage:OgImage = null;
    public var ogType:String = "game";
    
}

@:structInit class OgImage {
    
    public var image:String;
    public var type:String = "image/png";
    public var width:Int;
    public var height:Int;
    
    //TODO construct from asset reference
    
}
