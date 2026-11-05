--!strict
-- Player-facing text for every refusal code in docs/ARCHITECTURE.md.

local TEXT: { [string]: string } = {
	BadCell = "That spot isn't on the grid.",
	OutOfBounds = "That spot is outside your dungeon.",
	OnEntrance = "The entrance can't be built on.",
	UnknownRoom = "That room doesn't exist.",
	NotPlaceable = "That room can't be placed.",
	TooManyOfRoom = "You can only place one of that room.",
	Branch = "The path splits here. Keep it one single path.",
	Loop = "The path loops back on itself. Keep a gap between rooms.",
	Disconnected = "This room isn't connected to the entrance.",
	TreasureNotLast = "The Treasure Room must be the last room.",
	ProfileNotLoaded = "Your data isn't loaded yet. Please wait or rejoin.",
	RateLimited = "Slow down a little.",
	BadArgs = "Something went wrong with that request.",
	EncounterActive = "An adventurer is inside. Wait until they leave.",
	NotOwned = "You don't own that room.",
	DuplicateInstance = "That room is placed twice.",
	TooManyRooms = "You have too many rooms. Scrap some unplaced rooms first.",
	NotEnoughCoins = "Not enough coins.",
	NotForSale = "That isn't for sale.",
	MaxLevel = "Already at the highest level.",
	ChallengerLocked = "The Armored Challenger isn't unlocked yet.",
	ChallengerQueued = "A challenger is already on the way.",
	NothingToBank = "Your vault is empty.",
	NotBuilding = "Enter build mode first.",
	TutorialSkipLocked = "Finish your first adventurer before skipping the tutorial.",
	Busy = "Busy, try again in a moment.",
	LevelLocked = "Reach a higher keeper level to buy that room.",
	NoBox = "You don't have a box of that kind.",
	NotCraftable = "That room can't be crafted or scrapped.",
	NotEnoughBlueprints = "Not enough blueprints to craft that room.",
	RoomPlaced = "Remove that room from your dungeon before scrapping it.",
	NotScrappable = "That room can't be scrapped.",
	LastDefender = "Keep at least one defender room. Scrapping it would leave you defenseless.",
	ChallengerCooldown = "The Armored Challenger needs time to recover before returning.",
	BlueprintsFull = "You can't hold more blueprints of that room.",
	UnknownUpgrade = "That upgrade doesn't exist.",
}

local ReasonText = {}

function ReasonText.Get(code: any): string
	return TEXT[code] or "Something went wrong. Please try again."
end

return ReasonText
