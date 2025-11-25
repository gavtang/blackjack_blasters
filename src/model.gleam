import gleam/dict.{type Dict}
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import tiramisu
import tiramisu/asset
import tiramisu/effect.{type Effect}

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
}

pub type Model {
  Model(
    time: Float,
    textures: Dict(String, asset.Texture),
    loading_complete: Bool,
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
  let model = Model(time: 0.0, textures: dict.new(), loading_complete: False)

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
      let new_time = model.time +. ctx.delta_time
      #(Model(..model, time: new_time), effect.tick(Tick), None)
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
