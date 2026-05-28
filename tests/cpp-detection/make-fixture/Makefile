# Minimal Makefile fixture for harness-anchor cpp-detect.sh tests.
CXX      ?= c++
CXXFLAGS ?= -std=c++20 -Wall -Wextra -O2

app: src/main.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

.PHONY: clean
clean:
	rm -f app
