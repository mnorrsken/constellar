extends Node
## Events — global signal bus.
##
## Sim emits signals here; UI and render layers connect to them. UI must never
## poke Sim internals directly: it calls Sim methods and listens on this bus.
## Keep signals coarse and gameplay-meaningful; add them as milestones need them.

## Emitted after the world advanced one day (day = new day number).
signal day_passed(day: int)

## Emitted when the game speed changes (0 = paused).
signal speed_changed(speed: int)

## Ships were bought, sold, sent, refitted, arrived or departed.
signal fleet_changed

## A company's cash or loan changed.
signal company_changed(company_id: int)

## A short message for the player ("Wanderer arrived at Beta Hydri").
signal notice(text: String)

## A player ship sold cargo or delivered contracts: the profit (negative =
## loss) against what it paid, plus contract rewards, summed over one day.
signal profit(ship_id: int, amount: float)

## Contract boards were renewed, or a company took, delivered, failed or
## abandoned a contract.
signal contracts_changed

## The Rim Courier printed a headline: {day, text, systems, kind, start}.
signal news_posted(item: Dictionary)

## An event started or ended somewhere (markets, tariffs, lane danger or a
## government changed).
signal world_events_changed

## A player command was refused (the reason is also a notice).
signal refused(text: String)

## Bad news for the player: a ship raided or lost.
signal alert(text: String)

## A player action went through: "bought", "sold", "refitting",
## "servicing", "contract_accepted".
signal confirmed(kind: String)

## A company charted new systems (fog of war lifted).
signal charted(company_id: int)

## Something the player should look at and act on: one of their ships
## arrived or left the yard. The game has paused (if auto_pause is on).
signal attention(ship_id: int, system_index: int)
