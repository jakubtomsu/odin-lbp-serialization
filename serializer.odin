package game

import "core:fmt"
import "core:intrinsics"
import "core:mem"
import "core:runtime"
import "core:slice"

_ :: fmt // fmt is used only for debug printing

SERIALIZER_ENABLE_GENERIC :: #config(SERIALIZER_ENABLE_GENERIC, true)

// Explanation of the LBP serialization method:
// https://handmade.network/p/29/swedish-cubes-for-unity/blog/p/2723-how_media_molecule_does_serialization

// Each update to the data layout should be a value in this enum.
// WARNING: do not change the order of these!
Serializer_Version :: enum u32le {
    initial = 0,

    // Don't remove this!
    LATEST_PLUS_ONE,
}

SERIALIZER_VERSION_LATEST :: Serializer_Version(int(Serializer_Version.LATEST_PLUS_ONE) - 1)

Serializer :: struct {
    is_writing:  bool,
    data:        [dynamic]byte,
    read_offset: int,
    version:     Serializer_Version,
    debug:       Serializer_Debug,
}

when ODIN_DEBUG {
    Serializer_Debug :: struct {
        enable_debug_print: bool,
        depth:              int,
    }
} else {
    Serializer_Debug :: struct {}
}

// TODO: serialize with version
serializer_init_writer :: proc(
    s: ^Serializer,
    capacity: int = 1024,
    allocator := context.allocator,
    loc := #caller_location,
) -> mem.Allocator_Error {
    s^ = {
        is_writing = true,
        version    = SERIALIZER_VERSION_LATEST,
        data       = make([dynamic]byte, 0, capacity, allocator, loc) or_return,
    }
    return nil
}

// Warning: doesn't clone the data, make sure it stays available when deserializing!
serializer_init_reader :: proc(s: ^Serializer, data: []byte) {
    s^ = {
        is_writing = false,
        data       = transmute([dynamic]u8)runtime.Raw_Dynamic_Array{
            data = (transmute(runtime.Raw_Slice)data).data,
            len = len(data),
            cap = len(data),
            allocator = runtime.nil_allocator(),
        },
    }
}

serializer_clear :: proc(s: ^Serializer) {
    s.read_offset = 0
    clear(&s.data)
}

// The reader doesn't need to be destroyed, since it doesn't own the memory
serializer_destroy_writer :: proc(s: ^Serializer, loc := #caller_location) {
    assert(s.is_writing)
    delete(s.data, loc)
}

serializer_data :: proc(s: Serializer) -> []u8 {
    return s.data[:]
}

_serializer_debug_scope_indent :: proc(depth: int) {
    for i in 0 ..< depth do runtime.print_string("  ")
}

_serializer_debug_scope_end :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.enable_debug_print {
        s.debug.depth -= 1
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string("}\n")
    }
}

@(disabled = !ODIN_DEBUG, deferred_in = _serializer_debug_scope_end)
serializer_debug_scope :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.enable_debug_print {
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string(name)
        runtime.print_string(" {")
        runtime.print_string("\n")
        s.debug.depth += 1
    }
}

@(require_results, optimization_mode = "speed")
_serialize_bytes :: proc(s: ^Serializer, data: []byte, loc: runtime.Source_Code_Location) -> bool {
    when ODIN_DEBUG do if s.debug.enable_debug_print {
        _serializer_debug_scope_indent(s.debug.depth)
        fmt.printf("%i bytes, ", len(data))
        if s.is_writing {
            fmt.printf("written: %i\n", len(s.data))
        } else {
            fmt.printf("read: %i/%i\n", s.read_offset, len(s.data))
        }
    }

    if len(data) == 0 {
        return true
    }

    if s.is_writing {
        if _, err := append(&s.data, ..data); err != nil {
            when ODIN_DEBUG {
                panic("Serializer failed to append data", loc)
            }
            return false
        }
    } else {
        if len(s.data) < s.read_offset + len(data) {
            when ODIN_DEBUG {
                panic("Serializer attempted to read past the end of the buffer.", loc)
            }
            return false
        }
        copy(data, s.data[s.read_offset:][:len(data)])
        s.read_offset += len(data)
    }

    return true
}

@(require_results)
serialize_opaque :: #force_inline proc(s: ^Serializer, data: ^$T, loc := #caller_location) -> bool {
    return _serialize_bytes(s, #force_inline mem.ptr_to_bytes(data), loc)
}

// Serialize slice, fields are treated as opaque bytes.
@(require_results)
serialize_opaque_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "opaque slice")
    serialize_slice_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data^), loc)
}

// Serialize dynamic array, but leaves fields empty.
@(require_results)
serialize_slice_info :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "slice info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([]E, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, but leaves fields empty.
@(require_results)
serialize_dynamic_array_info :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "dynamic array info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([dynamic]E, num_items, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, fields are treated as opaque bytes.
@(require_results)
serialize_opaque_dynamic_array :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "opaque dynamic array")
    serialize_dynamic_array_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data[:]), loc)
}

when SERIALIZER_ENABLE_GENERIC {
    @(require_results)
    serialize_number :: proc(
        s: ^Serializer,
        data: ^$T,
        loc := #caller_location,
    ) -> bool where intrinsics.type_is_numeric(T) {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        return serialize_opaque(s, data, loc)
    }

    @(require_results)
    serialize_bit_set :: proc(s: ^Serializer, data: ^$T/bit_set[$E], loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        return serialize_opaque(s, data, loc)
    }

    @(require_results)
    serialize_enum :: proc(
        s: ^Serializer,
        data: ^$T,
        loc := #caller_location,
    ) -> bool where intrinsics.type_is_enum(T) {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)), false)
        return serialize_opaque(s, data, loc)
    }

    @(require_results)
    serialize_array :: proc(s: ^Serializer, data: ^$T/[$S]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        when intrinsics.type_is_numeric(E) {
            serialize_opaque(s, data, loc) or_return
        } else {
            for &v in data {
                serialize(s, &v, loc) or_return
            }
        }
        return true
    }

    @(require_results)
    serialize_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        serialize_slice_info(s, data, loc) or_return
        for &v in data {
            serialize(s, &v, loc) or_return
        }
        return true
    }

    @(require_results)
    serialize_string :: proc(s: ^Serializer, data: ^string, loc := #caller_location) -> bool {
        serializer_debug_scope(s, "string")
        return serialize_opaque_slice(s, transmute(^[]u8)data, loc)
    }

    @(require_results)
    serialize_dynamic_array :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        serialize_dynamic_array_info(s, data, loc) or_return
        for &v in data {
            serialize(s, &v, loc) or_return
        }
        return true
    }

    @(require_results)
    serialize_map :: proc(s: ^Serializer, data: ^$T/map[$K]$V, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        num_items := len(data)
        serialize_number(s, &num_items, loc) or_return

        if s.is_writing {
            for k, v in data {
                k_ := k
                v_ := v
                serialize(s, &k_, loc) or_return
                when size_of(V) > 0 {
                    serialize(s, &v_, loc) or_return
                }
            }
        } else {
            data^ = make_map(map[K]V, num_items)
            for _ in 0 ..< num_items {
                k: K
                v: V
                serialize(s, &k, loc) or_return
                when size_of(V) > 0 {
                    serialize(s, &v, loc) or_return
                }
                data[k] = v
            }
        }

        return true
    }
}



when SERIALIZER_ENABLE_GENERIC {
    serialize :: proc {
        serialize_number,
        serialize_bit_set,
        serialize_array,
        serialize_slice,
        serialize_string,
        serialize_dynamic_array,
        serialize_map,

        // Custom
        serialize_foo,
        serialize_bar,
    }
}

Foo :: struct {
    a:          i32,
    b:          f32,
    name:       string,
    big_buffer: []u8,
}

Bar :: struct {
    foos: [dynamic]Foo,
    data: map[i32]bit_set[0 ..< 8],
}

serialize_foo :: proc(s: ^Serializer, foo: ^Foo, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "foo") // optional
    serialize(s, &foo.a, loc) or_return
    serialize(s, &foo.b, loc) or_return
    serialize(s, &foo.name, loc) or_return
    {
        context.allocator = context.temp_allocator
        serialize(s, &foo.big_buffer, loc) or_return
    }
    return true
}

serialize_bar :: proc(s: ^Serializer, bar: ^Bar, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "bar")
    // you can but don't have to pass the `loc` parameter into the serialize procedures
    serialize(s, &bar.foos) or_return
    serialize(s, &bar.data) or_return
    return true
}


compare_bar :: proc(a, b: Bar) -> bool {
    compare_foo :: proc(a, b: Foo) -> bool {
        if a.name != b.name do return false
        if len(a.big_buffer) != len(b.big_buffer) do return false
        for v, i in a.big_buffer do if v != b.big_buffer[i] do return false
        return a.a == b.a && a.b == b.b
    }

    if len(a.foos) != len(b.foos) do return false
    for v, i in a.foos do if !compare_foo(v, b.foos[i]) do return false

    if len(a.data) != len(b.data) do return false
    for k, va in a.data {
        if vb, ok := b.data[k]; ok {
            if va != vb do return false
        }
    }

    return true
}

main :: proc() {
    s: Serializer
    serializer_init_writer(&s)
    when ODIN_DEBUG {
        s.debug.enable_debug_print = true
    }

    bar: Bar = {
        foos = {
            {a = 123, b = 0.1, name = "hello", big_buffer = {1, 2, 3, 4, 5}},
            {a = 1e9, b = -10e20, name = "bye", big_buffer = {}},
        },
        data = {-10 = {1, 0}, 23 = {2, 3}, 62 = {6, 2}},
    }

    fmt.println("Hello")
    fmt.println(bar)

    serialize_bar(&s, &bar)

    {
        data := s.data[:]
        s: Serializer
        serializer_init_reader(&s, data)
        new_bar: Bar
        serialize_bar(&s, &new_bar)

        fmt.println(new_bar)

        assert(compare_bar(bar, new_bar))
    }
}

/* Debug output from the bar structure above:

bar {
  [dynamic]Foo {
    dynamic array info {
      int {
        8 bytes, written: 0
      }
    }
    foo {
      i32 {
        4 bytes, written: 8
      }
      f32 {
        4 bytes, written: 12
      }
      string {
        opaque slice {
          slice info {
            int {
              8 bytes, written: 16
            }
          }
          5 bytes, written: 24
        }
      }
      []u8 {
        slice info {
          int {
            8 bytes, written: 29
          }
        }
        u8 {
          1 bytes, written: 37
        }
        u8 {
          1 bytes, written: 38
        }
        u8 {
          1 bytes, written: 39
        }
        u8 {
          1 bytes, written: 40
        }
        u8 {
          1 bytes, written: 41
        }
      }
    }
    foo {
      i32 {
        4 bytes, written: 42
      }
      f32 {
        4 bytes, written: 46
      }
      string {
        opaque slice {
          slice info {
            int {
              8 bytes, written: 50
            }
          }
          3 bytes, written: 58
        }
      }
      []u8 {
        slice info {
          int {
            8 bytes, written: 61
          }
        }
      }
    }
  }
  map[i32]bit_set[0..=7] {
    int {
      8 bytes, written: 69
    }
    i32 {
      4 bytes, written: 77
    }
    bit_set[0..=7] {
      1 bytes, written: 81
    }
    i32 {
      4 bytes, written: 82
    }
    bit_set[0..=7] {
      1 bytes, written: 86
    }
    i32 {
      4 bytes, written: 87
    }
    bit_set[0..=7] {
      1 bytes, written: 91
    }
  }
}
*/
