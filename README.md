# LBP serialization
This is a small drop-in code sample for binary [LBP](https://handmade.network/p/29/swedish-cubes-for-unity/blog/p/2723-how_media_molecule_does_serialization) serialization.

This method is good for 2 main reasons:
- You need only one procedure for both seralization and deserialization. This way they can't go out of sync
- Full backwards compatibility with all previous versions

## How to use
The serializer versioning and generic `serialize` procedure depend on other parts of your package, so the indented way of using this is to copy `serializer.odin` into your game package.

## Simple example
```odin
Entity :: struct {
  pos: [2]f32,
  health: f32,
  name: string,
}

entity_serialize :: proc(s: ^Serializer, entity: ^Entity, loc := #caller_location) -> bool {
  serialize(s, &entity.pos) or_return
  serialize(s, &entity.health) or_return
  serialize(s, &entity.name) or_return
  return true
}
```

## Contributions
All contributions are welcome, I'll try to merge them when I have time!
