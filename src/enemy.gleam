//// Enemies are small piles of cards that move around
//// Hitting them with a card attaches the card to the pile
//// Cards have a score by blackjack rules
//// On bust: base cards return to enemy deck
//// On blackjack: all cards return to player deck

import card
import gleam/float
import gleam/int
import gleam/list
import gleam_community/maths as math
import tiramisu/animation
import tiramisu/transform
import vec/vec3

pub type Enemy {
  Enemy(cards: List(card.Card), tween: animation.Tween(transform.Transform))
}

pub fn enemy_deck_base_vec() -> vec3.Vec3(Float) {
  vec3.Vec3(7.0, 1.0, 0.0)
}

pub fn enemy_base_deck() -> List(Enemy) {
  echo list.range(1, 13)
    |> list.flat_map(fn(i) {
      [
        card.CardDef(card.Hearts, card.Rank(i)),
        card.CardDef(card.Clubs, card.Rank(i)),
        card.CardDef(card.Spades, card.Rank(i)),
      ]
    })
    |> list.shuffle()
    |> list.index_map(fn(def, i) {
      let pos =
        enemy_deck_base_vec()
        |> transform.at()
        |> transform.translate(vec3.Vec3(0.0, int.to_float(i) *. 0.03, 0.0))
        |> transform.with_euler_rotation(vec3.Vec3(math.pi() /. 2.0, 0.0, 0.0))
      // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      Enemy(
        cards: [
          card.CardContained(
            i + 100,
            def,
            card.Enemy,
            animation.tween_transform(pos, pos, 1000.0, animation.EaseInOutSine),
          ),
        ],
        tween: animation.tween_transform(
          pos,
          pos,
          1000.0,
          animation.EaseInOutSine,
        ),
      )
    })
}

pub fn enemy_flatten_cards(enemies: List(Enemy)) -> List(card.Card) {
  enemies
  |> list.flat_map(fn(e) { e.cards })
}

pub fn random_valid_target() -> transform.Transform {
  // x: [-5, 5]
  // y: [0.5, 1.5]
  // z: [-5, 5]
  vec3.Vec3(
    float.random() *. 10.0 -. 5.0,
    float.random() +. 0.5,
    float.random() *. 10.0 -. 5.0,
  )
  |> transform.at()
  |> transform.with_euler_rotation(vec3.Vec3(math.pi() /. -2.0, 0.0, 0.0))
}

pub type Score {
  Score(low: Int, high: Int)
}

pub fn enemy_score(e: Enemy) -> Score {
  list.fold(e.cards, Score(0, 0), fn(acc, c) {
    case c {
      card.CardContained(
        _id,
        card.CardDef(_suit, card.Rank(rank)),
        _team,
        _tween,
      )
        if rank == 1
      -> Score(acc.low + 1, acc.high + 11)

      card.CardContained(_id, card.CardDef(_suit, rank), _team, _tween) ->
        Score(
          acc.low + card.rank_to_value(rank),
          acc.high + card.rank_to_value(rank),
        )
      _ -> acc
      // invaalid, should not be
    }
  })
}
