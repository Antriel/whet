package whet;

import whet.Whetstone;

class CacheManager {

    static var memCache:Map<Whetstone, WhetSource> = new Map();
    static var tempFiles:FileCache = new FileCache('.whet/.tmp/');

    static public function getSource(stone:Whetstone):WhetSource {
        switch stone.cacheMode {
            case NoCache:
                return stone.generateSource();
            case MemoryCache:
                var cached = memCache.get(stone);
                if (cached == null || cached.hash != stone.getHash()) {
                    cached = stone.generateSource();
                    memCache.set(stone, cached);
                }
                return cached;
            case FileCache:
                return null;
                // TODO
        }
    }

    static public function getFilePath(stone:Whetstone, ?fileId:SourceId):SourceId {
        if (fileId == null) fileId = "file";
        var fileCache:FileCache = null;

        if (stone.cacheMode.match(FileCache)) {
            // TODO implement
        } else {
            fileCache = tempFiles;
        }
        return fileCache.add(stone, fileId);
        // TODO clean tmp on start/end of process
    }

}

enum CacheMode {

    NoCache;
    MemoryCache;
    FileCache;

}

class FileCache {

    var map:Map<WhetstoneID, Array<SourceId>> = new Map();
    var folder:SourceId;

    public function new(folder:SourceId) {
        SourceId.assertDir(folder);
        this.folder = folder;
    }

    public function add(stoneId:WhetstoneID, fileId:SourceId):SourceId {
        if (!map.exists(stoneId)) map.set(stoneId, []);
        fileId = fileId.getPutInDir(folder);
        var allFiles = map.get(stoneId);
        var name = fileId.withoutExt;
        var counter = -1;
        do {
            fileId.withoutExt = counter >= 0 ? name + counter : name;
            counter++;
        } while (allFiles.indexOf(fileId) >= 0);
        allFiles.push(fileId);

        return fileId;
    }

}
