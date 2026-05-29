// main.cpp — e2e fixture entry point; parses CLI args and initializes Engine
#include "engine.h"
#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "Usage: %s <command>\n", argv[0]);
        return 1;
    }

    e2e::Engine engine;
    if (!engine.initialize()) {
        std::fprintf(stderr, "Engine initialization failed\n");
        return 1;
    }

    std::printf("e2e fixture running: %s\n", argv[1]);
    return 0;
}
