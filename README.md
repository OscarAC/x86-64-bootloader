# x86-64 Bootloader (Directly to Long Mode)

This bootloader will boot a kernel into long mode, and everything in a 512 Bytes binary

## Building Binaries

The assembler used  to generate the binary is the Netwide Assemble [nasm](https://www.nasm.us/)

```bash
nasm src/mbr.asm -o build/mbr.bin -f bin
```

## Usage

I'm not responsible for the usage of this code, it is presented here for educational purposes and example of bootstrapping a PC-AT system with a x86-64 processor.



## License
[GNU GENERAL PUBLIC LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html)
