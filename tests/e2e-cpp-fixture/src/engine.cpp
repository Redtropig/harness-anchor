// engine.cpp — Engine implementation; manages lifecycle and state
#include "engine.h"

namespace e2e {

Engine::Engine() : initialized_(false) {}

Engine::~Engine() {
    if (initialized_) {
        shutdown();
    }
}

bool Engine::initialize() {
    initialized_ = true;
    return true;
}

void Engine::shutdown() {
    initialized_ = false;
}

bool Engine::is_initialized() const {
    return initialized_;
}

} // namespace e2e
