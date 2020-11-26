const std = @import("std");
const clap = @import("clap");
const print = std.debug.print;

const argsAlloc = std.process.argsAlloc;
const argsFree = std.process.argsFree;
const getCwdAlloc = std.process.getCwdAlloc;

const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const page_allocator = std.heap.page_allocator;

const Program = struct {
    pc: usize,
    program: []u8,
    current_char: u8,
};

pub fn main() !void {
    
    const params = comptime [_]clap.Param(clap.Help) {
        clap.parseParam("-h, --help") catch unreachable,
        clap.parseParam("-s, --source <STR>") catch unreachable,
    };

    var diag: clap.Diagnostic = undefined;

    var args = clap.parse(clap.Help, &params, std.heap.page_allocator, &diag) catch |err| {
        diag.report(std.io.getStdErr().outStream(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.flag("--help"))
        print("--help                  Display this menu\n-s --source <filename>  Transpile brainfuck into zig\n", .{});
    if (args.option("--source")) |filename| {
        const input_flags = std.fs.File.OpenFlags {
            .read = true,
            .write = false,
        };

        const prgm = pr: {
            const program_file = std.fs.cwd().openFile(filename, input_flags) catch |err| {
                print("Unable to compile due to error: {}\n", .{err});
                return;
            };
            const size = try program_file.getEndPos();

            var buf = try page_allocator.alloc(u8, size);

            const bytes_real = try program_file.read(buf);

            break :pr buf;
        };
    
        var pr = Program {
            .pc = 0,
            .program = prgm,
            .current_char = undefined,
        };

        var line_len: u8 = 0;
        
        const flags = std.fs.File.CreateFlags {
            .read=false,
            .truncate=true,
            .exclusive = false,
        };

        const new_path = blk: {
            const dot_index = iblk: {
                for (filename) |char, idx| {
                    if (char == '.') {
                        break :iblk idx;
                    }
                }
                break :iblk 0;
            };
            if (dot_index == 0) { break :blk filename; }
            const new_name = filename[0..dot_index];
            break :blk try std.mem.concat(page_allocator, u8, &[_][]const u8{"compiled-zig/", new_name, ".zig"});
        };

        const file = try std.fs.cwd().createFile(new_path, flags);
        _=try file.write("const std=@import(\"std\");const print=std.debug.print;\n");
        _=try file.write("pub fn main()void{");
        _=try file.write("var p:usize=0;var t=[_]u8{0}**65535;\n");

        const w = file.writer();
        while (pr.pc < pr.program.len) : (pr.pc += 1) {
            if (line_len >= 70) {
                _=try file.write("\n");
                line_len = 0;
            }

            pr.current_char = pr.program[pr.pc];
            switch (pr.program[pr.pc]) {
                '>' => {
                    _=try w.print("p+={};", .{amount(&pr)});
                    line_len += 6;
                },
                '<' => {
                    _=try w.print("p-={};", .{amount(&pr)});
                    line_len += 6;
                },
                '+' => {
                    _=try w.print("_=@addWithOverflow(u8,t[p],{},&t[p]);", .{amount(&pr)});
                    line_len += 37;
                },
                '-' => {
                    _=try w.print("_=@subWithOverflow(u8,t[p],{},&t[p]);", .{amount(&pr)});
                    line_len += 37;
                },
                '[' => {
                    _=try file.write("while(t[p]>0){");
                    line_len += 14;
                },
                ']' => {
                    _=try file.write("}");
                    line_len += 1;
                },
                '.' => {
                    _=try file.write("print(\"{c}\",.{t[p]});");
                    line_len += 21;
                },
                else => {},
            }
        }
        _=try file.write("}");
    }
    print("compilation successful\n", .{});
}

fn amount(pr: *Program) u8 {
    var times: u8 = 0;
    while(pr.program[pr.pc] == pr.current_char) : (times += 1) {
        pr.pc += 1;
    }
    pr.pc -= 1;
    return times;
}