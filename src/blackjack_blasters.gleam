import gleam/option
import tiramisu
import tiramisu/background

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
