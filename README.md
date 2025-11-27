# blackjack_blasters

[![Package Version](https://img.shields.io/hexpm/v/blackjack_blasters)](https://hex.pm/packages/blackjack_blasters)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/blackjack_blasters/)

```sh
gleam add blackjack_blasters@1
```
```gleam
import blackjack_blasters

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://hexdocs.pm/blackjack_blasters>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Asset Credits

Cute Card Deck by Dani Maccari
<https://dani-maccari.itch.io/cute-cards>


## Planning and Todos
- Card ammo system: draw 3-5 face up before needing to reload
- Spin Lucy on reload, switch to the lucyhappy sprite
- Lucy starts with the diamond deck, other cards fly in face
  up like space invaders (possibly from cards on the ground)
- Implement collision detection
- On hit, cards stack. Bust: >21 destroys the enemy
- On blackjack: bonus points, maybe keep the enemy card?
- Implement poker chip projectile
    maybe score, maybe enemy bullets that deal damage (reduce score)

## Physics notes
- Need dynamic bodies for collisions to be detected
- Can't currently switch body types, need to delete items based on phase
- Node deletions are handled automatically based on diffing the node tree - but need different ID types
- This does mean aligning positions manually - whenever the item changes, grabbing the position to assign it an inital
- Alternatively: handle collision detection manually
