import gleam/dict.{type Dict}
import gleam/option.{None, Some}
import tiramisu
import tiramisu/background
import tiramisu/effect.{type Effect}

import model
import view

pub fn main() -> Nil {
  tiramisu.run(
    dimensions: option.None,
    background: background.Color(0x1a1a2e),
    init: model.init,
    update: model.update,
    view: view.view,
  )
}
