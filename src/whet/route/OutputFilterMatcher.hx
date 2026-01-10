package whet.route;

import whet.extern.Minimatch;

/**
 * Utility for matching queries against Stone output filters.
 * Enables skipping entire Stone subtrees when their outputs can't match a query.
 */
class OutputFilterMatcher {

    /**
     * Check if a query could possibly match a Stone's output filter.
     * Returns true if the Stone should be enumerated, false if it can be skipped.
     *
     * @param query The search pattern (often a specific file path)
     * @param filter The Stone's output filter (null = matches anything)
     * @param queryIsPattern True if query contains wildcards
     */
    public static function couldMatch(query:SourceId, filter:Null<OutputFilter>, queryIsPattern:Bool):Bool {
        if (filter == null) return true;  // No filter = could produce anything

        // Stage 1: Extension check
        if (filter.extensions != null) {
            var queryExt = getExtension(query);
            if (queryExt != null && !extensionMatches(queryExt, filter.extensions)) {
                return false;  // Extension mismatch - definitely skip
            }
            // If query has no extension (pattern like 'assets/**'), can't filter by ext
        }

        // Stage 2: Pattern check (only for specific file queries)
        if (!queryIsPattern && filter.patterns != null) {
            // Query is a specific file - check if it matches any output pattern
            for (pattern in filter.patterns) {
                // Use **/ prefix to match pattern at any route depth
                if (Minimatch.makeNew("**/" + pattern).match(query)) {
                    return true;  // Matches at least one pattern
                }
            }
            return false;  // Doesn't match any pattern
        }

        // Query is a pattern - would need pattern intersection check
        // For now, conservatively return true
        return true;
    }

    /**
     * Extract extension from path, supporting compound extensions.
     * "title.png" → "png"
     * "title.png.meta.json" → "png.meta.json"
     * Returns null if no extension or contains wildcard.
     */
    static function getExtension(path:SourceId):Null<String> {
        var name = path.withExt;  // filename with extension
        var firstDot = name.indexOf('.');
        if (firstDot == -1 || firstDot == name.length - 1) return null;
        var ext = name.substring(firstDot + 1).toLowerCase();
        // Ignore if extension contains wildcard
        if (ext.indexOf('*') != -1) return null;
        return ext;
    }

    /**
     * Check if query extension matches any filter extension.
     * Handles compound extensions: query "png.meta.json" matches filter "json" or "meta.json" or "png.meta.json"
     */
    static function extensionMatches(queryExt:String, filterExts:Array<String>):Bool {
        for (filterExt in filterExts) {
            if (queryExt == filterExt || StringTools.endsWith(queryExt, '.' + filterExt)) {
                return true;
            }
        }
        return false;
    }

}
