# A deliberately non-C/C++ project: no build system, no C/C++ sources.
# cpp-detect.sh must classify this as is_cpp_project=false (guards invariant #5:
# C/C++ skills must NOT activate in non-C/C++ projects).
def main():
    print("hello from a python-only project")


if __name__ == "__main__":
    main()
