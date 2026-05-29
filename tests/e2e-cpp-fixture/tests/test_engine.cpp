// test_engine.cpp — Unit tests for Engine class
#include "engine.h"
#include <gtest/gtest.h>

TEST(EngineTest, InitializeSucceeds) {
    e2e::Engine engine;
    EXPECT_TRUE(engine.initialize());
    EXPECT_TRUE(engine.is_initialized());
}

TEST(EngineTest, ShutdownClearsState) {
    e2e::Engine engine;
    engine.initialize();
    engine.shutdown();
    EXPECT_FALSE(engine.is_initialized());
}

TEST(EngineTest, DefaultNotInitialized) {
    e2e::Engine engine;
    EXPECT_FALSE(engine.is_initialized());
}
