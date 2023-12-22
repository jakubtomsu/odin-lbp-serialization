# LBP serialization
This is a small drop-in code sample for binary [LBP](https://handmade.network/p/29/swedish-cubes-for-unity/blog/p/2723-how_media_molecule_does_serialization) serialization.

The benefits of this method include:
- You need only one procedure for both seralization and deserialization. This way they can't go out of sync
- Full backwards compatibility with all previous versions
- no need for RTTI

## How to use
The serializer versioning and generic `serialize` procedure depend on other parts of your package, so the indented way of using this is to copy `serializer.odin` into your game package.

## Simple example
```odin
Entity :: struct {
  pos: [2]f32,
  health: f32,
  name: string,
  foo: i32, // Added in version 'Add_Foo'
}

entity_serialize :: proc(s: ^Serializer, entity: ^Entity, loc := #caller_location) -> bool {
  // useful for debugging. Set serializer.debug.enable_debug_print to true to enable logging
  serializer_debug_scope(s, "entity")
  serialize(s, &entity.pos) or_return
  serialize(s, &entity.health) or_return
  serialize(s, &entity.name) or_return
  if s.version >= .Add_Foo do serialize(s, &entity.foo) or_return
  return true
}
```


## Contributions
All contributions are welcome, I'll try to merge them when I have time!
