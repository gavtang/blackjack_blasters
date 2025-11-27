import card
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
import tiramisu/physics
import tiramisu/scene
import tiramisu/spritesheet
import tiramisu/texture
import tiramisu/transform
import vec/vec3

import gleam_community/maths as math
import tiramisu/debug

pub fn view(model: Model, ctx: tiramisu.Context(Id)) -> scene.Node(Id) {
  let assert Ok(cam) =
    camera.perspective(field_of_view: 75.0, near: 0.1, far: 1000.0)
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
        id: model.Platform,
        geometry: ground_geom,
        material: ground_mat,
        transform: transform.at(position: vec3.Vec3(0.0, -2.0, 0.0))
          |> transform.with_euler_rotation(vec3.Vec3(-1.57, 0.0, 0.0)),
        physics: None,
      ),
      view_card(model, ctx),
      view_card_backs(model, ctx),
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
fn view_card(model: Model, ctx: tiramisu.Context(Id)) -> scene.Node(Id) {
  let assert Some(physics_world) = ctx.physics_world
  case model.loading_complete {
    False ->
      scene.empty(
        id: model.CardContainer,
        transform: transform.identity,
        children: [],
      )
    True -> {
      model.cards
      |> list.map(fn(current_card) {
        // [
        dict.get(model.textures, "cards")
        |> result.map(fn(tex) {
          let assert Ok(cards_sheet) = spritesheet.from_grid(tex, 15, 4)
          let card_tex = texture.clone(tex)
          let card_id = model.CardProjectileId(current_card.id)
          let card_frame =
            spritesheet.apply_frame(
              cards_sheet,
              card_tex,
              card.to_spritesheet_index(current_card),
            )

          let card_physics = case current_card {
            card.CardProjectile(_, _, _, _) ->
              // TODO use real values
              Some(
                physics.new_rigid_body(physics.Dynamic)
                |> physics.with_collider(physics.Box(
                  transform.identity,
                  1.0,
                  1.0,
                  1.0,
                ))
                |> physics.with_mass(1.0)
                |> physics.with_restitution(0.4)
                |> physics.with_friction(0.6)
                |> physics.build(),
              )
            _ -> None
          }

          let default_transform =
            transform.at(model.player.position)
            |> transform.rotate_x(-1.57)
            |> transform.translate(vec3.Vec3(0.0, 0.0, -1.0))

          scene.mesh(
            id: card_id,
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
            transform: case physics.get_transform(physics_world, card_id) {
              Ok(t) -> t
              Error(Nil) -> default_transform
            },
            physics: card_physics,
          )
        })
        // ]
      })
      // |> list.flatten()
      |> result.values()
      |> scene.empty(
        id: model.CardContainer,
        transform: transform.identity,
        children: _,
      )
    }
  }
}

// Use instanced_mesh to draw card backs because they all use the same texture
fn view_card_backs(model: Model, ctx: tiramisu.Context(Id)) -> scene.Node(Id) {
  let assert Some(physics_world) = ctx.physics_world
  case model.loading_complete {
    False ->
      scene.empty(
        id: model.CardBacks(0),
        transform: transform.identity,
        children: [],
      )
    True -> {
      let transform_instances =
        model.cards
        |> list.map(fn(c) {
          let id = case c {
            card.CardProjectile(card_id, _, _, _) ->
              model.CardProjectileId(card_id)
          }

          physics.get_transform(physics_world, id)
        })
        |> result.values()
        |> list.map(fn(t) {
          t
          |> transform.translate(vec3.Vec3(0.0, 0.1, 0.0))
          |> transform.rotate_by(vec3.Vec3(0.0, math.pi(), 0.0))
        })

      [
        dict.get(model.textures, "cards")
        |> result.map(fn(tex) {
          let assert Ok(cards_sheet) = spritesheet.from_grid(tex, 15, 4)
          let card_tex = texture.clone(tex)

          let card_frame = spritesheet.apply_frame(cards_sheet, card_tex, 14)
          let assert Ok(geometry) = geometry.plane(width: 1.5, height: 2.0)

          let instance_count = list.length(transform_instances)
          scene.instanced_mesh(
            // HACK use the card length to force reloading on adding cards
            id: model.CardBacks(instance_count),
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
            instances: transform_instances,
          )
        }),
      ]
      |> result.values()
      |> scene.empty(
        id: model.CardBacksContainer,
        transform: transform.identity,
        children: _,
      )
    }
  }
}
