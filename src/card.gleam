import gleam/int
import gleam/list
import gleam_community/maths as math
import tiramisu/animation
import tiramisu/transform
import vec/vec3

pub type CardDef {
  CardDef(suit: Suit, rank: Rank)
}

pub type Card {
  CardProjectile(id: Int, def: CardDef, initialized: Bool, lifetime: Float)
  CardTransition(
    id: Int,
    def: CardDef,
    tween: animation.Tween(transform.Transform),
  )
  CardContained(
    id: Int,
    def: CardDef,
    team: Team,
    tween: animation.Tween(transform.Transform),
  )
  // TODO add info for kinematic move
}

pub type Suit {
  Clubs
  Diamonds
  Hearts
  Spades
}

pub type Team {
  Player
  Enemy
}

pub type Rank {
  Rank(Int)
}

pub fn to_spritesheet_index(card: Card) -> Int {
  case card.def {
    CardDef(Hearts, Rank(rank)) -> rank - 1
    CardDef(Spades, Rank(rank)) -> rank + 14
    CardDef(Diamonds, Rank(rank)) -> rank + 29
    CardDef(Clubs, Rank(rank)) -> rank + 44
  }
}

pub fn deck_base_vec() -> vec3.Vec3(Float) {
  vec3.Vec3(-7.0, 1.0, 5.0)
}

pub fn base_deck() -> List(Card) {
  list.range(1, 13)
  |> list.map(fn(i) { CardDef(Diamonds, Rank(i)) })
  |> list.shuffle()
  |> list.index_map(fn(def, i) {
    let pos =
      deck_base_vec()
      |> transform.at()
      |> transform.translate(vec3.Vec3(0.0, int.to_float(i) *. 0.03, 0.0))
      |> transform.with_euler_rotation(vec3.Vec3(math.pi() /. 2.0, 0.0, 0.0))
    CardTransition(
      i,
      def,
      animation.tween_transform(pos, pos, 1000.0, animation.EaseInOutSine),
    )
  })
}

pub fn rank_to_value(rank: Rank) -> Int {
  case rank {
    Rank(13) -> 10
    Rank(12) -> 10
    Rank(11) -> 10
    Rank(other) -> other
  }
}
