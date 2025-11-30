import card
import enemy
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam_community/maths as math
import tiramisu
import tiramisu/animation
import tiramisu/asset
import tiramisu/effect.{type Effect}
import tiramisu/input
import tiramisu/physics
import tiramisu/transform
import vec/vec3

pub type Id {
  MainCamera
  Scene
  Ambient
  Directional
  Lucy
  Platform
  Sphere
  CardContainer
  // FIXME MAYBE add more card id variants
  CardId(Int)
  CardProjectileId(Int)
  CardTransitionId(Int)
  CardContainedId(Int)
  CardBacks(Int)
  CardBacksContainer
  Debug(String)
}

pub type Model {
  Model(
    time: Float,
    next_id: Int,
    textures: Dict(String, asset.Texture),
    loading_complete: Bool,
    player: Player,
    cards: List(card.Card),
    // HACK CardProjectile ONLY
    deck: List(card.Card),
    // HACK CardTransition ONLY
    staged_cards: List(card.Card),
    card_cooldown: Float,
    reload_timer: Float,
    player_state: PlayerState,
    enemies: List(enemy.Enemy),
    enemy_deck: List(enemy.Enemy),
    blackjack_buffer: List(card.Card),
    bust_buffer: List(card.Card),
  )
}

pub type PlayerState {
  Ready
  Reloading
}

pub type Player {
  Player(
    position: vec3.Vec3(Float),
    input_rotation: vec3.Vec3(Float),
    reload_rotation: vec3.Vec3(Float),
  )
}

pub type Msg {
  NoOp
  Tick
  TextureLoaded(String, asset.Texture)
}

pub fn init(
  _ctx: tiramisu.Context(Id),
) -> #(Model, Effect(Msg), option.Option(_)) {
  let model =
    Model(
      time: 0.0,
      // HACK
      next_id: 1000,
      textures: dict.new(),
      loading_complete: False,
      player: Player(
        position: vec3.Vec3(0.0, 1.0, 7.0),
        input_rotation: vec3.splat(0.0),
        reload_rotation: vec3.splat(0.0),
      ),
      cards: [],
      deck: card.base_deck(),
      staged_cards: [],
      // WARN card projectiles ONLY
      card_cooldown: 0.0,
      reload_timer: 0.0,
      player_state: Ready,
      enemies: [],
      enemy_deck: enemy.enemy_base_deck(),
      blackjack_buffer: [],
      bust_buffer: [],
    )

  // create a physics world with no gravity
  let physics_world =
    physics.new_world(physics.WorldConfig(gravity: vec3.splat(0.0)))
  let sprite_urls = [
    #("lucy", "./lucy.png"),
    #("cards", "CuteCards.png"),
    #("lucyhappy", "./lucyhappy.png"),
  ]

  let load_effects =
    list.map(sprite_urls, fn(item) {
      let #(name, url) = item
      effect.from_promise(
        promise.map(asset.load_texture(url), fn(result) {
          case result {
            Ok(tex) -> TextureLoaded(name, tex)
            Error(_) -> NoOp
          }
        }),
      )
    })
  #(
    model,
    effect.batch([effect.tick(Tick), ..load_effects]),
    Some(physics_world),
  )
}

pub fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context(Id),
) -> #(Model, Effect(Msg), option.Option(_)) {
  let assert Some(physics_world) = ctx.physics_world
  case msg {
    NoOp -> #(model, effect.none(), ctx.physics_world)
    Tick -> {
      let dt = ctx.delta_time

      // |> physics.apply_force(CardId(1), vec3.Vec3(0.0, 0.0, 0.01))
      let new_time = model.time +. dt

      // Handle player input
      let move_speed = 5.0
      let dx = case
        input.is_key_pressed(ctx.input, input.KeyD),
        input.is_key_pressed(ctx.input, input.KeyA)
      {
        True, False -> move_speed *. dt /. 1000.0
        False, True -> 0.0 -. move_speed *. dt /. 1000.0
        _, _ -> 0.0
      }

      let #(physics_world, new_cards) =
        model.cards
        |> list.fold(#(physics_world, []), fn(acc, c) {
          let #(world, cards_acc) = acc
          let assert card.CardProjectile(_, _, _, _) = c
          // HACK
          case c.initialized {
            True -> #(world, [c, ..cards_acc])
            False -> #(
              physics.apply_impulse(
                world,
                CardProjectileId(c.id),
                vec3.Vec3(0.0, 0.0, -8.0),
              )
                |> physics.apply_torque_impulse(
                  CardProjectileId(c.id),
                  vec3.Vec3(0.0, 0.9, 0.1),
                ),
              [card.CardProjectile(..c, initialized: True), ..cards_acc],
            )
          }
        })

      let new_cards = list.reverse(new_cards)

      let #(new_cards, next_id, new_staged_cards, new_card_cooldown) = case
        input.is_key_just_pressed(ctx.input, input.Space),
        model.card_cooldown,
        model.reload_timer,
        model.staged_cards
      {
        True, 0.0, 0.0, [first, ..rest] -> {
          #(
            new_cards
              |> list.append([
                card.CardProjectile(
                  def: first.def,
                  id: model.next_id + 1,
                  initialized: False,
                  lifetime: 2.0,
                ),
              ]),
            model.next_id + 1,
            rest,
            400.0,
          )
        }
        _, _, _, _ -> #(
          new_cards,
          model.next_id,
          model.staged_cards,
          model.card_cooldown,
        )
      }

      // get cards returning to deck
      let #(new_cards, d_returning_cards) =
        new_cards
        |> list.map(fn(c) {
          case c {
            card.CardProjectile(_, _, True, lifetime) ->
              card.CardProjectile(
                ..c,
                lifetime: lifetime -. ctx.delta_time /. 1000.0,
              )
            _ -> c
          }
        })
        |> list.partition(fn(c) {
          case c {
            card.CardProjectile(_, _, True, lifetime) if lifetime <=. 0.0 ->
              False
            _ -> True
          }
        })
      // add returning cards from blackjack and bust buffers
      let d_returning_cards =
        d_returning_cards
        |> list.append(model.blackjack_buffer)
        |> list.append(
          model.bust_buffer
          |> list.filter(fn(buster) {
            case buster {
              card.CardContained(_, _, card.Player, _) -> True
              _ -> False
            }
          }),
        )

      let deck_base_vec = card.deck_base_vec()
      let #(deck_bump_n, d_returning_cards) =
        list.map_fold(d_returning_cards, 0.0, fn(acc, d_card) {
          // Get physics for initial position
          let end =
            transform.at(deck_base_vec)
            |> transform.translate(vec3.Vec3(0.0, acc, 0.0))
            |> transform.with_euler_rotation(vec3.Vec3(
              math.pi() /. 2.0,
              0.0,
              0.0,
            ))
          let start = case
            physics.get_transform(physics_world, CardProjectileId(d_card.id)),
            d_card
          {
            Ok(trans), _ -> trans
            Error(Nil), card.CardContained(_, _, _, tween) ->
              animation.get_tween_value(tween)
            Error(Nil), _ -> end
          }

          #(
            acc +. 0.03,
            card.CardTransition(
              d_card.id,
              d_card.def,
              animation.tween_transform(
                start,
                end,
                1000.0,
                animation.EaseInOutSine,
              ),
            ),
          )
        })

      // bump existing deck up by the amount of cards added to the bottom
      let bumped_deck =
        list.map(model.deck, fn(card_to_bump) {
          case card_to_bump {
            card.CardTransition(id, def, tween) ->
              card.CardTransition(
                id,
                def,
                animation.Tween(
                  ..tween,
                  end_value: tween.end_value
                    |> transform.translate(vec3.Vec3(0.0, deck_bump_n, 0.0)),
                ),
              )
            _ -> card_to_bump
          }
        })
      let new_returning_cards = list.append(d_returning_cards, bumped_deck)

      // apply kinematic movement and update tweens
      let #(physics_world, new_deck) =
        new_returning_cards
        |> list.map_fold(physics_world, fn(phy, c) {
          case c {
            card.CardTransition(id, def, tween) -> {
              let new_card =
                card.CardTransition(
                  id,
                  def,
                  tween |> animation.update_tween(dt),
                )
              let v = animation.get_tween_value(new_card.tween)
              let new_physics =
                physics.set_kinematic_translation(
                  phy,
                  CardTransitionId(id),
                  transform.position(v),
                )
              #(new_physics, new_card)
            }
            _ -> #(phy, c)
          }
        })

      let #(enemy_deck_bump_n, returning_enemy_cards) =
        model.bust_buffer
        |> list.filter(fn(buster) {
          case buster {
            card.CardContained(_, _, card.Enemy, _) -> True
            _ -> False
          }
        })
        |> list.map_fold(0.0, fn(acc, c) {
          let end =
            transform.at(enemy.enemy_deck_base_vec())
            |> transform.translate(vec3.Vec3(0.0, acc, 0.0))
            |> transform.with_euler_rotation(vec3.Vec3(
              math.pi() /. 2.0,
              0.0,
              0.0,
            ))
          let start = case c {
            card.CardContained(_, _, _, tween) ->
              animation.get_tween_value(tween)
            _ -> end
          }

          #(
            acc +. 0.03,
            enemy.Enemy(
              [
                card.CardContained(
                  c.id,
                  c.def,
                  card.Enemy,
                  animation.tween_transform(
                    start,
                    end,
                    1000.0,
                    animation.EaseInOutSine,
                  ),
                ),
              ],
              animation.tween_transform(
                start,
                end,
                1000.0,
                animation.EaseInOutSine,
              ),
            ),
          )
        })

      let new_enemy_deck = list.append(returning_enemy_cards, model.enemy_deck)
      // TODO implement cards returning to enemy deck

      let new_enemy_deck =
        list.map(new_enemy_deck, fn(enemy_to_bump) {
          let enemy.Enemy(cards, tween) = enemy_to_bump
          enemy.Enemy(
            cards,
            animation.Tween(
              ..tween,
              end_value: tween.end_value
                |> transform.translate(vec3.Vec3(0.0, enemy_deck_bump_n, 0.0)),
            ),
          )
        })

      let #(physics_world, new_enemy_deck) =
        new_enemy_deck
        |> list.map_fold(physics_world, fn(phy, e) {
          let enemy.Enemy(cards, tween) = e
          let new_tween = tween |> animation.update_tween(dt)
          let new_cards =
            cards
            |> list.map(fn(c) {
              case c {
                card.CardContained(id, def, team, _) ->
                  card.CardContained(id, def, team, new_tween)
                _ -> c
              }
            })
          let new_enemy = enemy.Enemy(new_cards, new_tween)
          let v = animation.get_tween_value(new_enemy.tween)

          // these should be length one. should be structured differently, :L
          let new_physics =
            list.fold(cards, phy, fn(phy2, c) {
              physics.set_kinematic_translation(
                phy2,
                CardContainedId(c.id),
                transform.position(v),
              )
            })

          #(new_physics, new_enemy)
        })

      // keep 5 enemies on the screen at a time
      let #(new_enemies, new_enemy_deck) = case
        list.length(model.enemies),
        list.reverse(new_enemy_deck)
      {
        enemies_length, [first, ..rest] if enemies_length < 3 -> #(
          [first, ..model.enemies],
          list.reverse(rest),
        )
        _, _ -> #(model.enemies, new_enemy_deck)
      }

      // update enemy movement
      // update tweens and set new end target if finished
      let new_enemies =
        new_enemies
        |> list.map(fn(e) {
          let e = case e.tween.elapsed {
            elapsed if elapsed >=. e.tween.duration ->
              enemy.Enemy(
                ..e,
                tween: animation.tween_transform(
                  e.tween.end_value,
                  enemy.random_valid_target(),
                  2500.0,
                  animation.EaseInOutSine,
                ),
              )
            _ -> enemy.Enemy(..e, tween: animation.update_tween(e.tween, dt))
          }
          let #(_, new_enemy_cards) =
            e.cards
            |> list.map_fold(0.0, fn(acc, c) {
              case c {
                card.CardContained(id, def, team, _tween) -> #(
                  acc +. 1.0,
                  card.CardContained(
                    id,
                    def,
                    team,
                    animation.Tween(
                      ..e.tween,
                      start_value: e.tween.start_value
                        |> transform.translate(vec3.Vec3(
                          acc *. 0.9,
                          acc *. 0.01,
                          acc *. 0.3,
                        )),
                      end_value: e.tween.end_value
                        |> transform.translate(vec3.Vec3(
                          acc *. 0.9,
                          acc *. 0.01,
                          acc *. 0.3,
                        )),
                    ),
                  ),
                )
                _ -> #(acc, c)
              }
            })

          enemy.Enemy(..e, cards: new_enemy_cards)
        })

      // Update player position
      let field_size = 10.0
      let new_player_position =
        vec3.Vec3(
          float.clamp(
            model.player.position.x +. dx,
            0.0 -. field_size /. 2.0,
            field_size /. 2.0,
          ),
          model.player.position.y,
          model.player.position.z,
        )

      // Update rotation state for direction indicator
      let new_player_input_rotation =
        vec3.splat(0.0)
        |> vec3.replace_z(float.clamp(
          model.player.input_rotation.z *. 0.95 -. dx *. math.pi() /. 6.0,
          -0.25,
          0.25,
        ))

      // Reload staged cards from deck
      let staged_base_vec = vec3.Vec3(1.0, -1.5, 7.0)
      let #(new_deck, new_staged, new_reload_timer) = case
        new_staged_cards,
        list.reverse(new_deck)
      {
        [], [one, two, three, ..rest] -> {
          let new_staged =
            [one, two, three]
            |> list.index_map(fn(c, i) {
              case c {
                card.CardTransition(id, def, tween) -> {
                  let current = animation.get_tween_value(tween)
                  card.CardTransition(
                    id,
                    def,
                    animation.Tween(
                      ..tween,
                      elapsed: 0.0,
                      start_value: current,
                      end_value: transform.at(staged_base_vec)
                        |> transform.translate(vec3.Vec3(
                          0.0 -. int.to_float(i),
                          0.0,
                          0.0 -. int.to_float(i) *. 0.02,
                        )),
                    ),
                  )
                }
                _ -> c
              }
            })
          #(list.reverse(rest), new_staged, 1000.0)
        }
        _, _ -> #(new_deck, new_staged_cards, model.reload_timer)
      }

      let #(physics_world, new_staged) =
        new_staged
        |> list.map_fold(physics_world, fn(phy, c) {
          case c {
            card.CardTransition(id, def, tween) -> {
              let new_card =
                card.CardTransition(
                  id,
                  def,
                  tween |> animation.update_tween(dt),
                )
              let v = animation.get_tween_value(tween)
              let new_physics =
                physics.set_kinematic_translation(
                  phy,
                  CardTransitionId(id),
                  transform.position(v),
                )
              #(new_physics, new_card)
            }
            _ -> #(phy, c)
          }
        })

      let new_physics_world = physics.step(physics_world, ctx.delta_time)
      let collision_events =
        physics.get_collision_events(new_physics_world)
        |> list.filter_map(fn(event) {
          case event {
            physics.CollisionStarted(
              CardContainedId(enemy_id),
              CardProjectileId(player_card_id),
            ) -> {
              // map through to get the card def from id
              let found_card =
                list.find(new_cards, fn(c) { player_card_id == c.id })
              case found_card {
                Ok(card.CardProjectile(_, def, _, _)) ->
                  Ok(#(def, player_card_id, enemy_id))
                _ -> Error("not a real card ?")
              }
            }
            physics.CollisionStarted(
              CardProjectileId(player_card_id),
              CardContainedId(enemy_id),
            ) -> {
              // map through to get the card def from id
              // something something DRY
              let found_card =
                list.find(new_cards, fn(c) { player_card_id == c.id })
              case found_card {
                Ok(card.CardProjectile(_, def, _, _)) ->
                  Ok(#(def, player_card_id, enemy_id))
                _ -> Error("not a real card ?")
              }
            }
            _ -> Error("do not care about this collision")
          }
        })

      let ids_to_remove =
        collision_events
        |> list.map(fn(event) {
          let #(_, id, _) = event
          id
        })

      let enemy_ids_gaining =
        collision_events
        |> list.map(fn(event) {
          let #(_, _, id) = event
          id
        })

      let new_cards =
        list.filter(new_cards, fn(c) { !list.contains(ids_to_remove, c.id) })

      let new_enemies =
        list.map(new_enemies, fn(enemy) {
          case
            list.any(enemy.cards, fn(enemy_card) {
              list.contains(enemy_ids_gaining, enemy_card.id)
            })
          {
            True -> {
              let eids = list.map(enemy.cards, fn(e) { e.id })
              let relevant_event =
                list.find(collision_events, fn(event) {
                  let #(_def, _pid, eid) = event
                  list.contains(eids, eid)
                })
              case relevant_event {
                Ok(#(def, id, _)) -> {
                  let new_cards =
                    list.append(enemy.cards, [
                      card.CardContained(id, def, card.Player, enemy.tween),
                    ])
                  enemy.Enemy(..enemy, cards: new_cards)
                }
                _ -> {
                  enemy
                }
              }
            }
            False -> enemy
          }
        })

      let #(cards_to_explode, new_enemies) =
        list.partition(new_enemies, fn(e) {
          case enemy.enemy_score(e) {
            enemy.Score(21, _) -> True
            enemy.Score(_, 21) -> True
            enemy.Score(low, _) if low > 21 -> True
            enemy.Score(_, _) -> False
          }
        })

      let #(blackjacks, busts) =
        list.partition(cards_to_explode, fn(e) {
          case enemy.enemy_score(e) {
            enemy.Score(21, _) -> True
            enemy.Score(_, 21) -> True
            enemy.Score(_, _) -> False
          }
        })

      let blackjack_cards =
        blackjacks
        |> list.flat_map(fn(e) { e.cards })
      let bust_cards =
        busts
        |> list.flat_map(fn(e) { e.cards })

      #(
        Model(
          ..model,
          time: new_time,
          player: Player(
            ..model.player,
            position: new_player_position,
            input_rotation: new_player_input_rotation,
          ),
          cards: new_cards,
          deck: new_deck,
          staged_cards: new_staged,
          next_id: next_id,
          card_cooldown: float.max(new_card_cooldown -. dt, 0.0),
          reload_timer: float.max(new_reload_timer -. dt, 0.0),
          enemy_deck: new_enemy_deck,
          enemies: new_enemies,
          blackjack_buffer: blackjack_cards,
          bust_buffer: bust_cards,
        ),
        effect.tick(Tick),
        Some(new_physics_world),
      )
    }
    TextureLoaded(name, tex) -> {
      let new_textures = dict.insert(model.textures, name, tex)
      let loading_complete = dict.size(new_textures) >= 1
      #(
        Model(..model, textures: new_textures, loading_complete:),
        effect.none(),
        ctx.physics_world,
      )
    }
  }
}
