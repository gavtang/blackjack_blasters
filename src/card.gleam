pub type CardDef {
  CardDef(suit: Suit, rank: Rank)
}

pub type Card {
  CardProjectile(id: Int, def: CardDef, initialized: Bool, lifetime: Float)
  // CardTransition(id: Int, def: CardDef)
  // TODO add info for kinematic move
}

pub type Suit {
  Clubs
  Diamonds
  Hearts
  Spades
}

pub type Rank {
  Rank(Int)
}

// TODO make real
pub fn to_spritesheet_index(card: Card) -> Int {
  let Rank(i) = card.def.rank
  i
}
