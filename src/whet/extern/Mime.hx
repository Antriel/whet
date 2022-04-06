package whet.extern;

@:jsRequire('mime', 'default')
extern class Mime {

    public static function getType(extension:String):String;
    public static function getExtension(mime:String):String;

}
