# riscv.zig

### A fast-ish interpreted RISC-V emulator, in pure Zig.

## About:
<p>riscv.zig is a work in progress RISC-V emulator, soon-to-be available as both a library that can be implemented in other projects and as a standalone application. The goal is to be as flexible as reasonably possible, supporting most (if not all) major ISA extensions. It also aims to be performant, at least for an interpreted emulator. (I plan to implement JIT compilation using GNU Lightning, and maybe even KVM later on.)<p>

> [!WARNING]
> riscv.zig is currently in heavy development, and is not in a usable state whatsoever. It probably can't even compile yet. As such, until I can get it into a usable state, all pushes and commits will be put into the main branch.

## Installation: 
The project tracks the latest stable releases of Zig, currently at 0.15.1. You will need the relevant version to use, and I strongly recommend you use [anyzig](https://github.com/marler8997/anyzig) to help with that. To clone and compile:
```bash
# You can also use ssh if you want:
git clone https://github.com/WGrav01/riscv.zig.git

cd riscv.zig

# To compile the library and executable (the exe is not implemented yet!):
zig build

# To run tests:
zig test

# To run the exe:
./zig-out/bin/riscv_zig
```
### How to add the library to an existing project
1) Run `zig fetch --save https://github.com/WGrav01/riscv.zig.git`. You should then see the library in your `build.zig.zon`.
2) Add to your `build.zig`:
    ```zig
    const riscv = b.dependency("riscv_zig", .{
            .target = target,
            .optimize = optimize,
    });
    ```
    And, before `installArtifact` is called: (this assumes your main module is called `exe`)
    ```zig
    exe.root_module.addImport("", riscv.module("riscv_zig"));
    ```
3) Now, you can use the library in your project 
    ```zig
    const riscv = @import("riscv");
    ```
4) Profit

## Usage:
Coming soon, once I have an actual implementation of the library.

## Roadmap:
| Feature         | Status                   |
|-----------------|--------------------------|
| RV32 support    | In progress              |
| RV32i support   | Planned                  |
| RV64 support    | Planned                  |
| RV128 support   | Planned                  |
| ISA extensions  | Status table coming soon |
| JIT compilation | Planned                  |
| GDB server      | Likely, not sure yet     |
| Assembler       | Possibly? Stretch goal   |
| Disassembler    | Possibly? Stretch goal   |

## Contributing:
PRs and help is welcome! Please open an issue however before any major contributions however.

## Support:
I will be happy to help you. However, please do not open an issue unless you are confident that your problem is an enhancement, bug, or something to change. Use discussions instead.

## Licensing:
This project is licensed under the [MIT License](https://opensource.org/license/MIT). You can view it in this repository [here](https://github.com/WGrav01/riscv.zig/blob/main/LICENSE.md).

## Credits:
- Inspired heavily by [mini-rv32ima](https://github.com/cnlohr/mini-rv32ima)
- A lot of info used from [fmash16's project](https://fmash16.github.io/content/posts/riscv-emulator-in-c.html).
- As well as from *[Writing a RISC-V Emulator in Rust](https://book.rvemu.app/index.html)*.
- Huge thanks to [Andrew Kelly](https://andrewkelley.me/) for creating the Zig language.