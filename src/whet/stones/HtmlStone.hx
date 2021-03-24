package whet.stones;

class HtmlStone extends Whetstone<HtmlConfig> {

    public function new(config:HtmlConfig) {
        if (config.title == null && config.project != null) config.title = config.project.config.name;
        if (config.meta != null && config.meta.description == null)
            config.meta.description = config.project.config.description;
        super(config);
    }

    public function clone(id:WhetstoneId = null):HtmlStone {
        var cloneConfig = config.clone();
        if (id != null) cloneConfig.id = id;
        return new HtmlStone(cloneConfig);
    }

    public function addBodyScript(src:String) {
        config.bodyElements.push('<script type="text/javascript" src="$src"></script>');
        return this;
    }

    public function addGameCss() {
        config.headElements.push('<style>
            html, body {
                margin: 0;
                padding: 0;
                height: 100%;
                width: 100%;
            }
            body {
                -webkit-tap-highlight-color: rgba(0, 0, 0, 0);
                -webkit-touch-callout: none;
                -webkit-text-size-adjust: none;
                -webkit-user-select: none;
                user-select: none;
                overflow: hidden;
                min-height: 100%;
                min-width: 100%;
            }</style>'
        );
        return this;
    }

    public function getContent():String {
        var sb = new StringBuf();
        sb.add('<!DOCTYPE html>\n');
        sb.add('<html lang="en">\n');
        sb.add('<head>\n');
        sb.add('\t<meta charset="utf-8"/>\n');
        if (config.title != null && config.title != "") {
            sb.add('\t<title>${config.title}</title>\n');
            sb.add('\t<meta property="og:title" content="${config.title}">\n');
        }
        if (config.stylePaths != null) for (path in config.stylePaths)
            sb.add('\t<link rel="stylesheet" href="$path">\n');
        if (config.meta != null) {
            var description = config.meta.description;
            if (description != null && description != "") {
                sb.add('\t<meta name="description" content="${description}">\n');
                sb.add('\t<meta property="og:description" content="${description}">\n');
            }
            var keywords = config.meta.keywords;
            if (keywords != null && keywords.length > 0) {
                sb.add('\t<meta name="keywords" content="${keywords.join(",")}">\n');
            }
            if (config.meta.viewport != null) sb.add('\t${config.meta.viewport.getString()}\n');
        }
        if (config.ogUrl != null && config.ogUrl != "")
            sb.add('\t<meta property="og:url" content="${config.ogUrl}">\n');
        if (config.ogImage != null) {
            var img = config.ogImage;
            sb.add('\t<meta property="og:image" content="${img.image}">\n');
            sb.add('\t<meta property="og:image:type" content="${img.type}" />\n');
            sb.add('\t<meta property="og:image:width" content="${img.width}">\n');
            sb.add('\t<meta property="og:image:height" content="${img.height}">\n');
        }
        if (config.ogType != null)
            sb.add('\t<meta property="og:type" content="${config.ogType}">\n');
        for (el in config.headElements)
            sb.add(el.split('\n').map(line -> '\t$line').join('\n'));
        sb.add('</head>\n');
        var bodyAtts = config.bodyElementAtts.join(' ');
        if (bodyAtts.length > 0) bodyAtts = " " + bodyAtts;
        sb.add('<body$bodyAtts>\n');

        for (el in config.bodyElements)
            sb.add(el.split('\n').map(line -> '\t$line').join('\n') + '\n');
        sb.add('</body>\n');
        sb.add('</html>');
        return sb.toString();
    }

    function generate(hash):Array<WhetSourceData> return [WhetSourceData.fromString(config.id, getContent())];

    override function list():Array<SourceId> return [config.id];

}

@:structInit class HtmlConfig extends WhetstoneConfig {

    public var headElements:Array<String> = [];
    public var bodyElements:Array<String> = [];
    public var meta:HtmlMetaConfig = null;
    public var stylePaths:Array<String> = null;
    public var title:String = null;
    public var ogUrl:String = null;
    public var ogImage:OgImage = null;
    public var ogType:String = "game";
    public var bodyElementAtts:Array<String> = [];

    public function clone():HtmlConfig return {
        project: this.project,
        id: this.id,
        cacheStrategy: this.cacheStrategy,
        headElements: this.headElements.copy(),
        bodyElements: this.bodyElements.copy(),
        meta: this.meta == null ? null : this.meta.clone(),
        stylePaths: this.stylePaths == null ? null : this.stylePaths.copy(),
        title: this.title,
        ogUrl: this.ogUrl,
        ogImage: this.ogImage == null ? null : this.ogImage.clone(),
        ogType: this.ogType,
        bodyElementAtts: this.bodyElementAtts.copy()
    };

}

@:structInit class OgImage {

    public var image:String;
    public var type:String = "image/png";
    public var width:Int;
    public var height:Int;

    // TODO construct from asset reference

    public function clone():OgImage return {
        image: this.image,
        type: this.type,
        width: this.width,
        height: this.height,
    };

}

@:structInit class HtmlMetaConfig {

    public var description:String = null;
    public var keywords:Array<String> = null;
    public var viewport:HtmlViewportMeta = null;

    public function clone():HtmlMetaConfig return {
        description: this.description,
        keywords: this.keywords == null ? null : this.keywords.copy(),
        viewport: this.viewport == null ? null : this.viewport.clone()
    };

}

@:structInit class HtmlViewportMeta {

    public static final NoScale:HtmlViewportMeta = {
        width: 'device-width',
        initialScale: '1.0',
        maximumScale: '1.0',
        minimumScale: '1.0',
        userScalable: 'no'
    };

    var width:String = null;
    var initialScale:String = null;
    var maximumScale:String = null;
    var minimumScale:String = null;
    var userScalable:String = null;

    public function clone():HtmlViewportMeta return {
        width: this.width,
        initialScale: this.initialScale,
        maximumScale: this.maximumScale,
        minimumScale: this.minimumScale,
        userScalable: this.userScalable
    };

    public function getString() return '<meta name="viewport" content="${getContent().join(", ")}">';

    function getContent() {
        var content = [];
        if (width != null) content.push('width=$width');
        if (initialScale != null) content.push('initial-scale=$initialScale');
        if (maximumScale != null) content.push('maximum-scale=$maximumScale');
        if (minimumScale != null) content.push('minimum-scale=$minimumScale');
        if (userScalable != null) content.push('user-scalable=$userScalable');
        return content;
    }

}
