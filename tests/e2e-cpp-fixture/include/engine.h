// engine.h — Engine class interface; RAII over runtime state
#ifndef E2E_ENGINE_H
#define E2E_ENGINE_H

namespace e2e {

class Engine {
public:
    Engine();
    ~Engine();

    bool initialize();
    void shutdown();
    bool is_initialized() const;

private:
    bool initialized_;
};

} // namespace e2e

#endif // E2E_ENGINE_H
