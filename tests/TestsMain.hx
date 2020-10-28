function main() {
    whet.Utils.deleteRecursively('.whet');
    utest.UTest.run([
        new TestRemoteFileStone(),
        new TestRouter(),
        // new TestNpmManager()
    ]);

}
