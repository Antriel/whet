function main() {
    // TODO should clean up .whet before each test.
    utest.UTest.run([
        new TestRemoteFileStone(),
        new TestRouter()
    ]);

}
