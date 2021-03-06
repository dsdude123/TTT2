function CreateFavTable()
	if not sql.TableExists("ttt_bem_fav") then
        query = ("CREATE TABLE ttt_bem_fav (guid TEXT, role TEXT, weapon_id TEXT)")
		result = sql.Query(query)
	else
		print("ALREADY EXISTS")
	end
end

function AddFavorite(guid, role, weapon_id)
    query = ("INSERT INTO ttt_bem_fav VALUES('" .. guid .. "','" .. role .. "','" .. weapon_id .. "')")
    result = sql.Query(query)
end

function RemoveFavorite(guid, role, weapon_id)
    query = ("DELETE FROM ttt_bem_fav WHERE guid = '" .. guid .. "' AND role = '" .. role .. "' AND weapon_id = '" .. weapon_id .. "'")
    result = sql.Query(query)
end

function GetFavorites(guid, role)
    query = ("SELECT weapon_id FROM ttt_bem_fav WHERE guid = '" .. guid .. "' AND role = '" .. role .. "'")
    result = sql.Query(query)

    return result
end

-- looks for weapon id in favorites table (result of GetFavorites)
function IsFavorite(favorites, weapon_id)
	for _, value in pairs(favorites) do
		local dbid = value["weapon_id"]
        
        if dbid == tostring(weapon_id) then
            return true
        end
    end
    
    return false
end
