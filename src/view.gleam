import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import model.{type Id, type Model}
import tiramisu
import tiramisu/camera
import tiramisu/geometry
import tiramisu/light
import tiramisu/material
import tiramisu/scene
import tiramisu/spritesheet
import tiramisu/texture
import tiramisu/transform
import vec/vec3

import gleam_community/maths as math
import tiramisu/debug

pub fn view(model: Model, _ctx: tiramisu.Context(Id)) -> scene.Node(Id) {
  let assert Ok(cam) =
    camera.perspective(field_of_view: 75.0, near: 0.1, far: 1000.0)
  let assert Ok(sphere_geom) =
    geometry.sphere(radius: 1.0, width_segments: 32, height_segments: 32)
  let assert Ok(sphere_mat) =
    material.new() |> material.with_color(0x0066ff) |> material.build
  let assert Ok(ground_geom) = geometry.plane(width: 20.0, height: 20.0)
  let assert Ok(ground_mat) =
    material.new() |> material.with_color(0x808080) |> material.build

  let camera =
    scene.camera(
      id: model.MainCamera,
      camera: cam,
      transform: transform.at(position: vec3.Vec3(0.0, 6.5, 11.0)),
      look_at: Some(vec3.Vec3(0.0, 0.0, 0.0)),
      active: True,
      viewport: None,
      postprocessing: None,
    )

  let lights = [
    scene.light(
      id: model.Ambient,
      light: {
        let assert Ok(light) = light.ambient(color: 0xffffff, intensity: 1.3)
        light
      },
      transform: transform.identity,
    ),
    scene.light(
      id: model.Directional,
      light: {
        let assert Ok(light) =
          light.directional(color: 0xffffff, intensity: 1.9)
        light
      },
      transform: transform.at(position: vec3.Vec3(10.0, 10.0, 10.0)),
    ),
  ]

  scene.empty(
    id: model.Scene,
    transform: transform.identity,
    children: [
      camera,
      scene.mesh(
        id: model.Sphere,
        geometry: sphere_geom,
        material: sphere_mat,
        transform: transform.at(position: vec3.Vec3(0.0, 0.0, 0.0)),
        physics: None,
      ),
      scene.mesh(
        id: model.Platform,
        geometry: ground_geom,
        material: ground_mat,
        transform: transform.at(position: vec3.Vec3(0.0, -2.0, 0.0))
          |> transform.with_euler_rotation(vec3.Vec3(-1.57, 0.0, 0.0)),
        physics: None,
      ),
      view_card(model),
      view_card_backs(model),
      view_lucy(model),

      debug.axes(model.Debug("axes"), vec3.splat(0.0), 5.0),
      // debug.grid(model.Debug("grid"), 20.0, 20, debug.color_white),
    ]
      |> list.append(lights),
  )
}

fn view_lucy(model: Model) -> scene.Node(Id) {
  case model.loading_complete {
    False ->
      scene.empty(id: model.Lucy, transform: transform.identity, children: [])
    True ->
      [
        dict.get(model.textures, "lucy")
        |> result.map(fn(tex) {
          scene.mesh(
            id: model.Lucy,
            geometry: {
              let assert Ok(geometry) = geometry.plane(width: 2.0, height: 2.0)
              geometry
            },
            material: {
              let assert Ok(material) =
                material.new()
                |> material.with_color(0xffffff)
                |> material.with_color_map(tex)
                |> material.with_transparent(True)
                |> material.with_metalness(0.1)
                |> material.with_roughness(0.5)
                |> material.build()
              material
            },
            transform: transform.at(position: model.player.position)
              |> transform.rotate_x(-1.57)
              // rotate to lay flat
              |> transform.rotate_z(-0.13)
              // slight adjustment to account for sprite angle
              |> transform.rotate_by(model.player.input_rotation),
            physics: None,
          )
        }),
      ]
      |> result.values()
      |> scene.empty(id: model.Lucy, transform: transform.identity, children: _)
  }
}

// TODO handle many cards
fn view_card(model: Model) -> scene.Node(Id) {
  case model.loading_complete {
    False ->
      scene.empty(
        id: model.Card(1),
        transform: transform.identity,
        children: [],
      )
    True ->
      [
        dict.get(model.textures, "cards")
        |> result.map(fn(tex) {
          let assert Ok(cards_sheet) = spritesheet.from_grid(tex, 15, 4)
          let card_tex = texture.clone(tex)

          let card_frame = spritesheet.apply_frame(cards_sheet, card_tex, 1)

          scene.mesh(
            id: model.Card(1),
            geometry: {
              let assert Ok(geometry) = geometry.plane(width: 1.5, height: 2.0)
              geometry
            },
            material: {
              let assert Ok(material) =
                material.new()
                |> material.with_color(0xffffff)
                |> material.with_color_map(card_frame)
                |> material.with_transparent(True)
                |> material.with_metalness(0.1)
                |> material.with_roughness(0.5)
                |> material.build()
              material
            },
            transform: transform.at(position: vec3.Vec3(-1.0, 1.3, 1.0))
              |> transform.with_euler_rotation(vec3.Vec3(
                -1.57,
                // 0.001 *. model.time,
                0.001 *. model.time,
                0.001 *. model.time,
              )),
            physics: None,
          )
        }),
      ]
      |> result.values()
      |> scene.empty(
        id: model.Card(1),
        transform: transform.identity,
        children: _,
      )
  }
}

// Use instanced_mesh to draw card backs because they all use the same texture
fn view_card_backs(model: Model) -> scene.Node(Id) {
  case model.loading_complete {
    False ->
      scene.empty(
        id: model.CardBacks,
        transform: transform.identity,
        children: [],
      )
    True ->
      [
        dict.get(model.textures, "cards")
        |> result.map(fn(tex) {
          let assert Ok(cards_sheet) = spritesheet.from_grid(tex, 15, 4)
          let card_tex = texture.clone(tex)

          let card_frame = spritesheet.apply_frame(cards_sheet, card_tex, 14)
          let assert Ok(geometry) = geometry.plane(width: 1.5, height: 2.0)

          let instance =
            transform.at(position: vec3.Vec3(-3.0, 1.0, 1.0))
            |> transform.with_euler_rotation(vec3.Vec3(0.0, 0.0, 0.0))
          let instance2 =
            transform.at(position: vec3.Vec3(-3.0, 3.0, 2.0))
            |> transform.with_euler_rotation(vec3.Vec3(
              0.0,
              0.0,
              0.0 +. 0.01 *. model.time,
            ))
          let instance3 =
            transform.at(position: vec3.Vec3(-1.0, 1.3, 1.0))
            |> transform.with_euler_rotation(vec3.Vec3(
              -1.57,
              math.pi() +. 0.001 *. model.time,
              0.001 *. model.time,
            ))

          scene.instanced_mesh(
            id: model.CardBacks,
            geometry:,
            material: {
              let assert Ok(material) =
                material.new()
                |> material.with_color(0xffffff)
                |> material.with_color_map(card_frame)
                |> material.with_transparent(True)
                |> material.with_metalness(0.1)
                |> material.with_roughness(0.5)
                |> material.build()
              material
            },
            instances: [instance, instance2, instance3],
          )
        }),
      ]
      |> result.values()
      |> scene.empty(
        id: model.CardBacks,
        transform: transform.identity,
        children: _,
      )
  }
}
