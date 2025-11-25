import gleam/dict.{type Dict}
import gleam/float
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam_community/maths as math
import tiramisu
import tiramisu/asset
import tiramisu/effect.{type Effect}
import tiramisu/input
import vec/vec3

pub type Id {
  MainCamera
  Scene
  Ambient
  Directional
  Lucy
  Platform
  Sphere
  Card(Int)
  CardBacks
  Debug(String)
}

pub type Model {
  Model(
    time: Float,
    textures: Dict(String, asset.Texture),
    loading_complete: Bool,
    player: Player,
  )
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
      textures: dict.new(),
      loading_complete: False,
      player: Player(
        position: vec3.Vec3(0.0, 1.0, 7.0),
        input_rotation: vec3.splat(0.0),
        reload_rotation: vec3.splat(0.0),
      ),
    )

  let sprite_urls = [#("lucy", "./lucy.png"), #("cards", "CuteCards.png")]

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
  #(model, effect.batch([effect.tick(Tick), ..load_effects]), None)
}

pub fn update(
  model: Model,
  msg: Msg,
  ctx: tiramisu.Context(Id),
) -> #(Model, Effect(Msg), option.Option(_)) {
  case msg {
    NoOp -> #(model, effect.none(), None)
    Tick -> {
      let dt = ctx.delta_time
      let new_time = model.time +. dt

      let move_speed = 5.0
      let dx = case
        input.is_key_pressed(ctx.input, input.KeyD),
        input.is_key_pressed(ctx.input, input.KeyA)
      {
        True, False -> move_speed *. dt /. 1000.0
        False, True -> 0.0 -. move_speed *. dt /. 1000.0
        _, _ -> 0.0
      }

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

      let new_player_input_rotation =
        vec3.splat(0.0)
        |> vec3.replace_z(float.clamp(
          model.player.input_rotation.z *. 0.95 -. dx *. math.pi() /. 6.0,
          -0.25,
          0.25,
        ))

      #(
        Model(
          ..model,
          time: new_time,
          player: Player(
            ..model.player,
            position: new_player_position,
            input_rotation: new_player_input_rotation,
          ),
        ),
        effect.tick(Tick),
        None,
      )
    }
    TextureLoaded(name, tex) -> {
      let new_textures = dict.insert(model.textures, name, tex)
      let loading_complete = dict.size(new_textures) >= 1
      #(
        Model(..model, textures: new_textures, loading_complete:),
        effect.none(),
        None,
      )
    }
  }
}
