--!strict
-- Who may use the admin chat commands (AdminService). The check runs on the
-- server only: a player is an admin if their UserId is listed here OR their rank
-- in GroupId is at least MinRank (cached per player for the session).

return table.freeze({
	UserIds = table.freeze({ 855002824 }),
	GroupId = 33284082,
	MinRank = 254,
})
