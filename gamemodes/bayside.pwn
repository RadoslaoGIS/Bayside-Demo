/*
================================================================================

							  Bayside Demo by Radek
							  
		Version 1.0
  		- MySQL R41-4 login/register and house system (ORM and CACHE)
		- Vehicles from .csv file system
		- Class selection

================================================================================
																			  */

// Includes
#include <a_samp> // SA-MP Functions - SA-MP Team
#include <a_mysql> // MySQL R41-4 - pBlueG
#include <sscanf2> // sscanf2 - Y-LESS
#include <streamer> // streamer - Incognito
#include <zcmd> //zcmd - ZeeX

// MySQL configuration
#define	MYSQL_HOST "127.0.0.1" // MySQL Host
#define	MYSQL_USER "root" // MySQL Username
#define MYSQL_PASS "" // MySQL Password
#define	MYSQL_BASE "samp" // MySQL Database

// Default spawn point (Bayside)
#define DEFAULT_POS_X -2238.0 // Pos X
#define DEFAULT_POS_Y 2352.0 // Pos Y
#define DEFAULT_POS_Z 4.98 // Pos Z
#define DEFAULT_POS_A 135.0 // Angle

// Class selection point (Bayside)
#define CLASS_POS_X -2095.0 // Pos X
#define CLASS_POS_Y 2314.0 // Pos Y
#define CLASS_POS_Z 25.9 // Pos Z
#define CLASS_POS_A 90.0 // Angle

// Other defines
#undef MAX_PLAYERS
#define MAX_PLAYERS 500 // Max Players
#define MAX_HOUSES 100 // Max Houses

#define COLOR_GREEN 0x00B000AA // Green Color
#define COLOR_RED 0xFF0000AA // Red Color
#define COLOR_YELLOW 0xFFFF00AA // Yellow Color
#define COLOR_BLUE 0x0000FFAA // Blue Color

#define PICKUP_HOUSE 19524 //Yellow House Icon

#define DIALOG_UNUSED 0 // Dialog - Unused
#define DIALOG_LOGIN 1 // Dialog - Login
#define DIALOG_REGISTER 2 // Dialog - Register

#pragma tabsize 0

enum E_PLAYER // Player attributes enumeration
{
	ORM:ORM_ID,

	Player_ID,
	Name[MAX_PLAYER_NAME],
	Password[65],
	Salt[16],

	Skin,
	Score,
	Money,

	Float:X,
	Float:Y,
	Float:Z,
	Float:A,
	Interior,

	bool:LoggedIn,
	LoginAttempts
};

enum E_HOUSE // House attributes enumeration
{
	House_ID,
	Text3D:Label,
	Type[32],
	
	bool:Owned,
	Owner[24],
	bool:Locked,
	MapIcon,
	PickupModel,
	Price,
	InteriorID,
	
	Float:ExteriorX,
	Float:ExteriorY,
	Float:ExteriorZ,
	Float:InteriorX,
	Float:InteriorY,
	Float:InteriorZ,
	
	bool:CustInt,
 	bool:IDused
};

new MySQL:handle; // MySQL connection handle
new MySQLRaceCheck[MAX_PLAYERS]; // MySQL race check

new Player[MAX_PLAYERS][E_PLAYER]; // Array of player data
new House[MAX_HOUSES][E_HOUSE]; // Array of house data

new PlayerHouseID[MAX_PLAYERS]; // Stores the house ID the player is currently in

new vehicles = 0; // Default number of vehicles in the gamemode

forward OnPlayerDataLoaded(playerid, race_check); // Checks if the player is registered in MySQL database
forward OnPlayerRegister(playerid); // Registers player
forward LoadHouses(); // Loads houses from MySQL database
forward OnUpdateHouseOwner(playerid, houseid, owner[]); // Updates house owner
forward OnHouseSell(playerid, houseid); // Sells house
forward SendPlayerInside(playerid, houseid); // Sends player insise the house
forward SendPlayerOutside(playerid, houseid); // Sends player outsise the house
forward DelayedSpawn(playerid); // Spawns player with delay
forward DelayedKick(playerid); // Kicks player with delay

main()
{
	print("---------------------------------");
	print("    Bayside Demo by Radek 1.0    ");
	print("---------------------------------");
}

//============================================================================//
public OnGameModeInit()
{
	SetGameModeText("Bayside Demo 1.0"); // Gamemode Name

	for (new skinid = 0; skinid < 320; skinid++) // Loads skins to class selection
	{
		AddPlayerClass(skinid, DEFAULT_POS_X, DEFAULT_POS_Y, DEFAULT_POS_Z, DEFAULT_POS_A, 0, 0, 0, 0, 0, 0);
	}
	
 	vehicles += LoadStaticVehiclesFromFile("tierra.csv"); // Loads vehicles from .csv file

	new MySQLOpt:option_id = mysql_init_options(); // Creates MySQL options

	mysql_set_option(option_id, AUTO_RECONNECT, true); // It automatically reconnects when loosing connection to mysql server

	handle = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASS, MYSQL_BASE, option_id); // AUTO_RECONNECT is enabled for this connection handle only
	
	if (handle == MYSQL_INVALID_HANDLE || mysql_errno(handle) != 0)
	{
		print("MySQL connection failed. Server is shutting down.");
		SendRconCommand("exit"); // Close the server if there is no connection with MySQL
		return 1;
	}

	mysql_log(ERROR | WARNING);
	
	print("MySQL connection is successful.");

	SetupPlayerTable(); // Creates MySQL player database if it does not exist
	SetupHouseTable(); // Creates MySQL house database if it does not exist

	mysql_tquery(handle, "SELECT * FROM `houses`", "LoadHouses"); // Loads houses from MySQL database
	return 1;
}

//============================================================================//
public OnGameModeExit()
{
	// Saves all player data before closing connection
	for (new i = 0, j = GetPlayerPoolSize(); i <= j; i++) // GetPlayerPoolSize function was added in 0.3.7 version and gets the highest playerid currently in use on the server
	{
		if (IsPlayerConnected(i))
		{
			// Reason is set to 1 for normal 'Quit'
			OnPlayerDisconnect(i, 1);
		}
	}

	mysql_close(handle);
	
	// Resets all map icons, 3D text labels and pickups for houses
	DestroyAllDynamicMapIcons();
	DestroyAllDynamic3DTextLabels();
	DestroyAllDynamicPickups();
	return 1;
}

//============================================================================//
public OnPlayerRequestClass(playerid, classid)
{
	TogglePlayerSpectating(playerid, false); // Disables player spectating
	SetPlayerPos(playerid, CLASS_POS_X, CLASS_POS_Y, CLASS_POS_Z); // Skin position
	SetPlayerFacingAngle(playerid, 270.0); // Skin facing angle
	SetPlayerCameraPos(playerid, CLASS_POS_X+4.0, CLASS_POS_Y, CLASS_POS_Z); // Camera position
	SetPlayerCameraLookAt(playerid, CLASS_POS_X, CLASS_POS_Y, CLASS_POS_Z); // Directs camera to skin
	return 1;
}

//============================================================================//
public OnPlayerConnect(playerid)
{
	TogglePlayerSpectating(playerid, true); // Enables player spectating

	MySQLRaceCheck[playerid]++;

	static const empty_player[E_PLAYER];
	Player[playerid] = empty_player; // Resets player data

	GetPlayerName(playerid, Player[playerid][Name], MAX_PLAYER_NAME);

	new ORM:ormid = Player[playerid][ORM_ID] = orm_create("players", handle); // Creates orm instance and register all needed variables

	orm_addvar_int(ormid, Player[playerid][Player_ID], "id");
	
	orm_addvar_string(ormid, Player[playerid][Name], MAX_PLAYER_NAME, "name");
	orm_addvar_string(ormid, Player[playerid][Password], 65, "password");
	orm_addvar_string(ormid, Player[playerid][Salt], 16, "salt");
	
	orm_addvar_int(ormid, Player[playerid][Skin], "skin");
	orm_addvar_int(ormid, Player[playerid][Score], "score");
	orm_addvar_int(ormid, Player[playerid][Money], "money");
	
	orm_addvar_float(ormid, Player[playerid][X], "x");
	orm_addvar_float(ormid, Player[playerid][Y], "y");
	orm_addvar_float(ormid, Player[playerid][Z], "z");
	orm_addvar_float(ormid, Player[playerid][A], "a");
	orm_addvar_int(ormid, Player[playerid][Interior], "interior");
	
	orm_setkey(ormid, "name");

	orm_load(ormid, "OnPlayerDataLoaded", "dd", playerid, MySQLRaceCheck[playerid]); // Tells the orm system to load all data, assign it to our variables and call our callback when ready
	return 1;
}

//============================================================================//
public OnPlayerDisconnect(playerid, reason)
{
	MySQLRaceCheck[playerid]++;
	UpdatePlayerData(playerid, reason);
	Player[playerid][LoggedIn] = false; // Sets "LoggedIn" to false when the player disconnects, it prevents from saving the player data twice when "gmx" is used
	return 1;
}

//============================================================================//
public OnPlayerSpawn(playerid)
{
	TogglePlayerSpectating(playerid, false);
	SetCameraBehindPlayer(playerid);
	return 1;
}

//============================================================================//
public OnPlayerDeath(playerid, killerid, reason)
{
	TogglePlayerSpectating(playerid, true);
	SetSpawnInfo(playerid, NO_TEAM, Player[playerid][Skin], DEFAULT_POS_X, DEFAULT_POS_Y, DEFAULT_POS_Z, DEFAULT_POS_A, 0, 0, 0, 0, 0, 0);
	SetTimerEx("DelayedSpawn", 1000, false, "d", playerid);
	return 1;
}

//============================================================================//
public OnPlayerUpdate(playerid)
{
	if (GetPlayerInterior(playerid) == 2)
	{
		new Float:posx, Float:posy, Float:posz;
		GetPlayerPos(playerid, posx, posy, posz);

		if (posz < 999.0) SetPlayerPos(playerid, 1.1853, -3.2387, 999.428); // Protects the player from falling off the map inside the trailer
	}
	return 1;
}

//============================================================================//
public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch (dialogid)
	{
		case DIALOG_UNUSED: return 1; // Useful for dialogs that contain only information and we do nothing depending on whether they responded or not

		case DIALOG_LOGIN: // Login dialog
		{
			if (!response) return Kick(playerid);

			new hashed_pass[65];
			SHA256_PassHash(inputtext, Player[playerid][Salt], hashed_pass, 65);

			if (strcmp(hashed_pass, Player[playerid][Password]) == 0)
			{
				SendClientMessage(playerid, COLOR_GREEN, "You have been logged in."); // Password is correct

				Player[playerid][LoggedIn] = true;

				TogglePlayerSpectating(playerid, false);
				SetPlayerScore(playerid, Player[playerid][Score]);
 				ResetPlayerMoney(playerid);
 				GivePlayerMoney(playerid, Player[playerid][Money]);
 				SetPlayerInterior(playerid, Player[playerid][Interior]);
				SetSpawnInfo(playerid, NO_TEAM, Player[playerid][Skin], Player[playerid][X], Player[playerid][Y], Player[playerid][Z], Player[playerid][A], 0, 0, 0, 0, 0, 0);
				SpawnPlayer(playerid);
			}
			else
			{
			    Player[playerid][LoginAttempts]++;

			    if (Player[playerid][LoginAttempts] >= 3)
			    {
			        SendClientMessage(playerid, COLOR_RED, "You have mistyped the password 3 times.");
			        SetTimerEx("DelayedKick", 1000, false, "d", playerid);
			    }
			    else
			    {
			        SendClientMessage(playerid, COLOR_RED, "Wrong password! Try again.");
			        ShowLoginDialog(playerid);
			    }
			}
			return 1;
		}
		
		case DIALOG_REGISTER: // Register dialog
		{
			if (!response) return Kick(playerid);

			if (strlen(inputtext) >= 6)
			{
				// 16 random characters from 33 to 126 (in ASCII) for the salt
				for (new i = 0; i < 15; i++) Player[playerid][Salt][i] = random(94) + 33;
				SHA256_PassHash(inputtext, Player[playerid][Salt], Player[playerid][Password], 65);

				// Sends an INSERT query
				orm_save(Player[playerid][ORM_ID], "OnPlayerRegister", "d", playerid);
			}
			else
			{
				SendClientMessage(playerid, COLOR_RED, "You password must have at least 6 characters.");
				ShowRegisterDialog(playerid);
			}
			return 1;
		}

		default: return 0; // Dialog ID was not found, search in other scripts
	}
	return 1;
}

//============================================================================//
public OnPlayerDataLoaded(playerid, race_check)
{
	if (race_check != MySQLRaceCheck[playerid]) return Kick(playerid);

	orm_setkey(Player[playerid][ORM_ID], "id");

	switch (orm_errno(Player[playerid][ORM_ID])) // Checks if the player's name is in the MySQL database
	{
		case ERROR_OK: // Player's name was found in MySQL database
		{
			ShowLoginDialog(playerid);
		}
		case ERROR_NO_DATA: // Player's name wasn't found in MySQL database
		{
		    ShowRegisterDialog(playerid);
		}
	}
	return 1;
}

//============================================================================//
public OnPlayerRegister(playerid)
{
	SendClientMessage(playerid, COLOR_GREEN, "Account successfully registered! You have been automatically logged in. Choose your skin."); // Player has been successfully registered

	// Player data initialization
	Player[playerid][LoggedIn] = true;
	Player[playerid][X] = DEFAULT_POS_X;
	Player[playerid][Y] = DEFAULT_POS_Y;
	Player[playerid][Z] = DEFAULT_POS_Z;
	Player[playerid][A] = DEFAULT_POS_A;

	TogglePlayerSpectating(playerid, false);
	GivePlayerMoney(playerid, 10000);
	SetSpawnInfo(playerid, NO_TEAM, Player[playerid][Skin], DEFAULT_POS_X, DEFAULT_POS_Y, DEFAULT_POS_Z, DEFAULT_POS_A, 0, 0, 0, 0, 0, 0);
	return 1;
}

//============================================================================//
public DelayedSpawn(playerid)
{
	TogglePlayerSpectating(playerid, false);
	SpawnPlayer(playerid);
	return 1;
}

//============================================================================//
public DelayedKick(playerid)
{
	Kick(playerid);
	return 1;
}
//============================================================================//
public LoadHouses()
{
	if (!cache_num_rows()) return printf("\n[Houses]: 0 Houses were loaded.\n");

	new Label1[128], rows;
	cache_get_row_count(rows);

    for (new i = 0; i < rows && i < MAX_HOUSES; i++)
    {
		cache_get_value_name_int(i, "id", House[i][House_ID]);

		cache_get_value_name(i, "type", House[i][Type], 64);
		cache_get_value_name_int(i, "price", House[i][Price]);
		cache_get_value_name_int(i, "owned", bool:House[i][Owned]);
		cache_get_value_name_int(i, "locked", bool:House[i][Locked]);
		cache_get_value_name(i, "owner", House[i][Owner], MAX_PLAYER_NAME+1);

		cache_get_value_name_int(i, "in_id", House[i][InteriorID]);
		cache_get_value_name_float(i, "ex_x", House[i][ExteriorX]);
		cache_get_value_name_float(i, "ex_y", House[i][ExteriorY]);
		cache_get_value_name_float(i, "ex_z", House[i][ExteriorZ]);

		cache_get_value_name_float(i, "in_x", House[i][InteriorX]);
		cache_get_value_name_float(i, "in_y", House[i][InteriorY]);
		cache_get_value_name_float(i, "in_z", House[i][InteriorZ]);

		if (House[i][Owned] == true)
		{
			format(Label1, sizeof(Label1), "%s\nOwner: %s", House[i][Type], House[i][Owner]);
		}
		else
		{
			format(Label1, sizeof(Label1), "%s\n%s\nPrice: $%d\nUse /buy to buy this house.", House[i][Type], House[i][Owner], House[i][Price]);
			House[i][MapIcon] = CreateDynamicMapIcon(House[i][ExteriorX], House[i][ExteriorY], House[i][ExteriorZ], 31, 1);
		}

		House[i][PickupModel] = CreateDynamicPickup(PICKUP_HOUSE, 1, House[i][ExteriorX], House[i][ExteriorY], House[i][ExteriorZ], 0, 0);
		House[i][Label] = CreateDynamic3DTextLabel(Label1, COLOR_YELLOW, House[i][ExteriorX], House[i][ExteriorY], House[i][ExteriorZ]+0.5, 20.0, .testlos = 1, .streamdistance = 20.0);
		House[i][IDused] = true;
	}

	printf("[MySQL] %d Houses loaded.", rows);
	return 1;
}

//============================================================================//
public OnUpdateHouseOwner(playerid, houseid, owner[])
{
	format(House[houseid][Owner], 24, "%s", owner);
	new Label2[128];

	if (!strcmp(owner, "FOR SALE", true))
		House[houseid][Owned] = false;
	else House[houseid][Owned] = true;

	if (House[houseid][Owned] == true)
	{
		format(Label2, sizeof(Label2), "%s\nOwner: %s", House[houseid][Type], House[houseid][Owner]);
	}
	else
	{
		format(Label2, sizeof(Label2), "%s\n%s\nPrice: $%d\nUse /buy to buy this house.", House[houseid][Type], House[houseid][Owner], House[houseid][Price]);
	}
	
	UpdateDynamic3DTextLabelText(House[houseid][Label], COLOR_YELLOW, Label2);
	SendClientMessage(playerid, COLOR_GREEN, "You have bought this house!");
	return 1;
}

//============================================================================//
public OnHouseSell(playerid, houseid)
{
	House[houseid][Owned] = false;
	format(House[houseid][Owner], 24, "FOR SALE");

	new Label3[128], HouseCost = House[houseid][Price]/10*9;
	format(Label3, sizeof(Label3), "You sold your house for $%d.", HouseCost);
	SendClientMessage(playerid, COLOR_GREEN, Label3);
	GivePlayerMoney(playerid, HouseCost);

	format(Label3, sizeof(Label3), "%s\n%s\nPrice: $%d\nUse /buy to buy this house.", House[houseid][Type], House[houseid][Owner], House[houseid][Price]);
	UpdateDynamic3DTextLabelText(House[houseid][Label], COLOR_YELLOW, Label3);
	return 1;
}

//============================================================================//
public SendPlayerInside(playerid, houseid)
{
    if (houseid == MAX_HOUSES)
		return SendClientMessage(playerid, COLOR_RED, "You need to be at a house door.");

    new playername[MAX_PLAYER_NAME+1];
    GetPlayerName(playerid, playername, sizeof(playername));
    
    if (House[houseid][Locked] && House[houseid][Owned] && strcmp(playername, House[houseid][Owner], true) != 0)
       return SendClientMessage(playerid, COLOR_RED, "This house is locked.");

    SetPlayerPos(playerid, House[houseid][InteriorX], House[houseid][InteriorY], House[houseid][InteriorZ]);
    SetPlayerInterior(playerid, House[houseid][InteriorID]);
    SetPlayerVirtualWorld(playerid, House[houseid][House_ID]);

	PlayerHouseID[playerid] = houseid;
	SendClientMessage(playerid, COLOR_GREEN, "You entered the house.");
    return 1;
}

//============================================================================//
public SendPlayerOutside(playerid)
{
    new houseid = PlayerHouseID[playerid];

    if (houseid != MAX_HOUSES)
    {
        SetPlayerPos(playerid, House[houseid][ExteriorX], House[houseid][ExteriorY], House[houseid][ExteriorZ]);
        SetPlayerInterior(playerid, 0);
        SetPlayerVirtualWorld(playerid, 0);
        SendClientMessage(playerid, COLOR_GREEN, "You left the house.");
        PlayerHouseID[playerid] = MAX_HOUSES;
    }
    else SendClientMessage(playerid, COLOR_RED, "You're not inside a valid house.");
    return 1;
}

//============================================================================//
SetupPlayerTable()
{
	mysql_tquery(handle,
		"CREATE TABLE IF NOT EXISTS `players` ( \
		`id` int(10) NOT NULL AUTO_INCREMENT, \
		`name` varchar(24) NOT NULL, \
		`password` char(64) NOT NULL, \
		`salt` char(16) NOT NULL, \
		`skin` smallint NOT NULL, \
		`score` mediumint NOT NULL, \
		`money` mediumint NOT NULL, \
		`x` float NOT NULL, \
		`y` float NOT NULL, \
		`z` float NOT NULL, \
		`a` float NOT NULL, \
		`interior` smallint NOT NULL, \
 		PRIMARY KEY (`id`), \
		UNIQUE KEY `Name` (`name`))");
	return 1;
}

//============================================================================//
SetupHouseTable()
{
	mysql_tquery(handle, "CREATE TABLE IF NOT EXISTS `houses` ( \
	  `id` int(10) NOT NULL AUTO_INCREMENT, \
	  `type` varchar(32) NOT NULL, \
	  `price` int NOT NULL, \
	  `owned` tinyint NOT NULL, \
	  `locked` tinyint NOT NULL, \
	  `owner` varchar(24) DEFAULT 'FOR SALE', \
	  `in_id` int NOT NULL, \
	  `ex_x` float NOT NULL, \
	  `ex_y` float NOT NULL, \
	  `ex_z` float NOT NULL, \
	  `in_x` float NOT NULL, \
	  `in_y` float NOT NULL, \
	  `in_z` float NOT NULL, \
	  PRIMARY KEY (`id`));");
	return 1;
}

//============================================================================//
UpdatePlayerData(playerid, reason)
{
	if (Player[playerid][LoggedIn] == false) return 0;

	// If the client crashed, it's not possible to get the player's position in OnPlayerDisconnect callback
	if (reason == 1)
	{
		GetPlayerPos(playerid, Player[playerid][X], Player[playerid][Y], Player[playerid][Z]);
		GetPlayerFacingAngle(playerid, Player[playerid][A]);
	}

	// Gets player data
	Player[playerid][Interior] = GetPlayerInterior(playerid);
	Player[playerid][Skin] = GetPlayerSkin(playerid);
	Player[playerid][Score] = GetPlayerScore(playerid);
	Player[playerid][Money] = GetPlayerMoney(playerid);

	// orm_save sends an UPDATE query
	orm_save(Player[playerid][ORM_ID]);
	orm_destroy(Player[playerid][ORM_ID]);
	return 1;
}

//============================================================================//
GetNearbyHouse(playerid)
{
	for (new i = 0; i < MAX_HOUSES; i++)
	{
		if (GetPlayerDistanceFromPoint(playerid, House[i][ExteriorX], House[i][ExteriorY], House[i][ExteriorZ]) <= 2.0)
			return i;
	}
	return MAX_HOUSES;
}

//============================================================================//
GetHouseExitPoint(playerid)
{
	for (new i = 0; i < MAX_HOUSES; i++)
	{
		if (GetPlayerDistanceFromPoint(playerid, House[i][InteriorX], House[i][InteriorY], House[i][InteriorZ]) <= 1.0)
			return i;
	}
	return MAX_HOUSES;
}

//============================================================================//
stock ShowLoginDialog(playerid)
{
    new string[115];
	format(string, sizeof string, "{FFFFFF}Welcome {00AAFF}%s\n{FFFFFF}Your account is registered. Please login by entering your password:", Player[playerid][Name]);
	ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Login", string, "Login", "Abort");
}

//============================================================================//
stock ShowRegisterDialog(playerid)
{
    new string[115];
	format(string, sizeof string, "{FFFFFF}Welcome {00AAFF}%s\n{FFFFFF}You can register by entering your password:", Player[playerid][Name]);
	ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Registration", string, "Register", "Abort");
}

//============================================================================//
stock IsNumeric(const string[])
{
	for (new i = 0, j = strlen(string); i < j; i++)
	{
		if (string[i] > '9' || string[i] < '0') return 0;
	}
	return 1;
}

//============================================================================//
stock LoadStaticVehiclesFromFile(const filename[])
{
	// Loads vehicles from file - function from Grand Larceny gamemode by SA-MP Team
	new File:file_ptr;
	new line[256];
	new var_from_line[64];
	new index;
	new vehicles_loaded;
	
	new Model;
	new Float:SpawnX;
	new Float:SpawnY;
	new Float:SpawnZ;
	new Float:SpawnA;
	new Color1;
	new Color2;

	file_ptr = fopen(filename, filemode:io_read);
	if (!file_ptr) return 0;

	vehicles_loaded = 0;

	while (fread(file_ptr, line,256) > 0)
	{
	    index = 0;

	    // Model
  		index = token_by_delim(line, var_from_line, ',', index);
  		if (index == (-1)) continue;
  		Model = strval(var_from_line);
   		if (Model < 400 || Model > 611) continue;

  		// X, Y, Z, Angle
  		index = token_by_delim(line, var_from_line, ',', index+1);
  		if (index == (-1)) continue;
  		SpawnX = floatstr(var_from_line);

  		index = token_by_delim(line, var_from_line, ',', index+1);
  		if (index == (-1)) continue;
  		SpawnY = floatstr(var_from_line);

  		index = token_by_delim(line, var_from_line, ',', index+1);
  		if (index == (-1)) continue;
  		SpawnZ = floatstr(var_from_line);

  		index = token_by_delim(line, var_from_line, ',', index+1);
  		if (index == (-1)) continue;
  		SpawnA = floatstr(var_from_line);

  		// Color1, Color2
  		index = token_by_delim(line, var_from_line, ',', index+1);
  		if (index == (-1)) continue;
  		Color1 = strval(var_from_line);

  		index = token_by_delim(line, var_from_line, ';', index+1);
  		Color2 = strval(var_from_line);

  		AddStaticVehicleEx(Model, SpawnX, SpawnY, SpawnZ, SpawnA, Color1, Color2, (30*60)); // Respawn time: 30 minutes

		vehicles_loaded++;
	}

	fclose(file_ptr);
	printf("%d vehicles loaded from: %s", vehicles_loaded, filename);
	return vehicles_loaded;
}

//============================================================================//
stock token_by_delim(const string[], return_str[], delim, start_index)
{
	new x = 0;
	while(string[start_index] != EOS && string[start_index] != delim) {
	    return_str[x] = string[start_index];
	    x++;
	    start_index++;
	}
	return_str[x] = EOS;
	if(string[start_index] == EOS) start_index = (-1);
	return start_index;
}

//============================================================================//
CMD:buy(playerid, params[])
{
	new houseid = GetNearbyHouse(playerid);
	new playermoney = GetPlayerMoney(playerid);

	if (houseid == MAX_HOUSES) return SendClientMessage(playerid, COLOR_RED, "You need to be at a house to buy it.");
	if (House[houseid][Owned]) return SendClientMessage(playerid, COLOR_RED, "You need to be at a house which is on sale.");
	if ((House[houseid][Price]) > playermoney) return SendClientMessage(playerid, COLOR_RED, "You don't have enough money to buy this house.");

	new query[128], playername[MAX_PLAYER_NAME+1], housecost = House[houseid][Price];
	GivePlayerMoney(playerid, -housecost);
	SendPlayerInside(playerid, houseid);
	GetPlayerName(playerid, playername, sizeof(playername));
	mysql_format(handle, query, sizeof(query), "UPDATE `houses` SET `owner` = '%s', `owned` = 1 WHERE `id` = %d", playername, House[houseid][House_ID]);
	mysql_tquery(handle, query, "OnUpdateHouseOwner", "iis", playerid, houseid, playername);
	return 1;
}

CMD:sell(playerid, params[])
{
	new houseid = GetNearbyHouse(playerid);

	if (houseid == MAX_HOUSES) return SendClientMessage(playerid, COLOR_RED, "You need to be at a house to buy it.");
	if (!House[houseid][Owned]) return SendClientMessage(playerid, COLOR_RED, "You need to be at a house which is not already on sale.");

	new query[128], playername[MAX_PLAYER_NAME+1], houseowner[MAX_PLAYER_NAME+1];
	GetPlayerName(playerid, playername, sizeof(playername));
	format(houseowner, sizeof(houseowner), "%s", House[houseid][Owner]);

	if (strcmp(houseowner, playername)) return SendClientMessage(playerid, COLOR_RED, "You need to be at a house that you own.");

	mysql_format(handle,query, sizeof(query), "UPDATE `houses` SET `owner` = 'FOR SALE', `owned` = 0, `locked` = 0 WHERE `id` = %d", House[houseid][House_ID]);
	mysql_tquery(handle,query, "OnHouseSell", "ii", playerid, houseid);
	return 1;
}

CMD:enter(playerid, params[])
{
	new houseid = GetNearbyHouse(playerid);
	SendPlayerInside(playerid, houseid);
	return 1;
}

CMD:exit(playerid, params[])
{
	new houseid = GetHouseExitPoint(playerid);
	SendPlayerOutside(playerid, houseid);
	return 1;
}

CMD:lock(playerid, params[])
{
	new houseid = GetNearbyHouse(playerid);
	
	if (houseid == MAX_HOUSES) return SendClientMessage(playerid, COLOR_RED, "You need to be at your house.");
	
	new playername[MAX_PLAYER_NAME+1], HouseOwner[MAX_PLAYER_NAME+1];
	GetPlayerName(playerid, playername, sizeof(playername));
	format(HouseOwner, sizeof(HouseOwner), "%s", House[houseid][Owner]);
	
	if (strcmp(playername, HouseOwner))
	{
		SendClientMessage(playerid, COLOR_RED, "You need to be at your house.");
		return 1;
	}
	
	if (House[houseid][Locked])
	{
		House[houseid][Locked] = false;
		new query[128];
		mysql_format(handle, query, sizeof(query), "UPDATE `houses` SET `locked` = 0 WHERE `id` = %d", House[houseid][House_ID]);
		mysql_tquery(handle, query);
		SendClientMessage(playerid, COLOR_GREEN, "You unlocked your house.");
	}
	
	else
	{
		House[houseid][Locked] = true;
		new query[128];
		mysql_format(handle, query, sizeof(query), "UPDATE `houses` SET `locked` = 1 WHERE `id` = %d", House[houseid][House_ID]);
		mysql_tquery(handle, query);
		
		SendClientMessage(playerid, COLOR_GREEN, "You locked your house.");
	}
	return 1;
}
