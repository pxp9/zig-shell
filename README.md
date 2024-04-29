## How to compile it and run the shell
1. Clone the repository
2. Open the terminal

```bash
cd zig-shell
```

3. Compile the code and run it

```bash
zig build run
```

This will generate the parser files

- src/parser/parser.c  from bison
- src/parser/parser.h  from bison
- src/parser/scanner.c from flex

and compile and execute the shell.
