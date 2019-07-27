const pluginConfig = require("./config");
const clusterUtil = require("./lib/clusterUtil.js");
const fs = require("fs");

const COMPRESS_LUA = false;

module.exports = class remoteCommands {
	constructor(mergedConfig, messageInterface, extras){
		this.messageInterface = messageInterface;
		this.config = mergedConfig;
		this.socket = extras.socket;
        this.registered = false;

        this.trainstopDB = {};
        this.zonesDB = {};

		let socketRegister = () => {
			this.socket.emit("registerTrainTeleporter", {
				instanceID: this.config.unique,
			});

            // no need for the setTimeout if the remote function is not just getting added via hotpatch
            let initInterval = setInterval(async () => {
                if(this.registered) {
                    this.messageInterface('/silent-command remote.call("trainTeleports", "setWorldId","' + this.config.unique + '")');
                    this.messageInterface('/silent-command remote.call("trainTeleports", "init")');
                    clearInterval(initInterval)
                }
            }, 5000);

            setInterval(async () => {
                this.messageInterface('/silent-command remote.call("trainTeleports", "reportPassedSecond")');
            }, 1000);
        };
		
		this.socket.on("hello", () => socketRegister());

		// initialize mod with Hotpatch
		(async () => {
			let startTime = Date.now();
			let hotpatchInstallStatus = await this.checkHotpatchInstallation();
			this.messageInterface("Hotpach installation status: "+hotpatchInstallStatus);
			if(hotpatchInstallStatus){
				var returnValue;
                var mainCode = await this.getSafeLua("sharedPlugins/trainTeleports/lua/trainTeleports.lua");

                var trainCode = await this.getSafeLua("sharedPlugins/trainTeleports/lua/train_tracking.lua");
                var trainstopCode = await this.getSafeLua("sharedPlugins/trainTeleports/lua/train_stop_tracking.lua");
                var guiCode = await this.getSafeLua("sharedPlugins/trainTeleports/lua/gui.lua");

                if(mainCode) returnValue = await messageInterface("/silent-command remote.call('hotpatch', 'update', '"+pluginConfig.name+"', '"+pluginConfig.version+"', '"+mainCode+"', \{train_tracking = '"+trainCode+"', train_stop_tracking = '"+trainstopCode+"', gui = '"+guiCode+"'\})");
                if(returnValue) console.log(returnValue);


				this.messageInterface("trainTeleports installed in "+(Date.now() - startTime)+"ms");
			} else {
				this.messageInterface("Hotpatch isn't installed! Please generate a new map with the hotpatch scenario to use trainTeleports.");
			}
		})().catch(e => console.error(e));

		this.socket.on("trainTeleporter_registered", async registered => {
		    this.registered = true;
        });

		this.socket.on("trainstopsDatabase", async trainstopsDB => {
		    console.log("got trainstops from master");
		    this.trainstopDB = trainstopsDB;
		    await this.applyTrainstopDB();
		});

        this.socket.on("zonesDatabase", async zonesDB => {
             console.log("got zones from master");
            this.zonesDB = zonesDB;
            await this.applyZonesDB();
            this.messageInterface('/silent-command remote.call("trainTeleports","json","' + this.singleEscape(JSON.stringify({event: "instances", data: await clusterUtil.getInstances(this.config, zonesDB)})) + '")');
        });


        this.socket.on("trainteleport_json", async data => {
//            this.messageInterface('/silent-command remote.call("trainTeleports","runCode", "game.print(\'≥\')")');
            this.messageInterface('/silent-command remote.call("trainTeleports","json","' + this.singleEscape(JSON.stringify(data)) + '")');
        });

        this.socket.on("trainstop_blocked", async data => {
            console.log("remote trainstop_blocked: "+data.name);
            let command = "/silent-command " + 'remote.call("trainTeleports", "runCode", "global.blockedStations[\"'+this.doubleEscape(data.name)+'\"] = true")';
            // console.log(command);
            this.messageInterface(command);
        });
        this.socket.on("trainstop_unblocked", async data => {
            console.log("remote trainstop_unblocked: "+data.name);
            let command = "/silent-command " + 'remote.call("trainTeleports", "runCode", "global.blockedStations[\"'+this.doubleEscape(data.name)+'\"] = nil")';
            // console.log(command);
            this.messageInterface(command);
        });
        this.socket.on("trainStopRenameSchedules", async data => {
            // console.log("rename stop in schedules: "+data.oldName+" to "+data.name+" for instance "+data.instanceID);
            this.messageInterface("/silent-command " + 'remote.call("trainTeleports", "updateStopInSchedules", "' +data.instanceID+ '", "'+this.doubleEscape(data.oldName)+'", "'+this.doubleEscape(data.name)+'")');
        });

	}

    singleEscape(stop) {
        stop = stop.replace(/\\/g, "\\\\");
        stop = stop.replace(/"/g, '\\"');
        stop = stop.replace(/'/g, "\\'");

        return stop
    }
    doubleEscape(stop) {
        stop = stop.replace(/\\/g, "\\\\\\\\");
        stop = stop.replace(/"/g, '\\\\\\"');
        stop = stop.replace(/'/g, "\\\'");

        return stop
    }


	async applyTrainstopDB(){
	    let trainstopsDB = this.trainstopDB;
        let command = 'remote.call("trainTeleports", "runCode", "global.trainstopsData = {';
        for(let instanceID in trainstopsDB){
            command += '{id='+instanceID+',';
            command += 'name=\\"'+await clusterUtil.getInstanceName(instanceID, this.config)+'\\",';
            command += 'stations={';
            for(let trainstop in trainstopsDB[instanceID]){
                command += '\\"'+this.doubleEscape(trainstop)+'\\",';
            }
            command += '}},';
        }
        command += '}';

        command += 'global.remoteStopZones = {}';
        for(let instanceID in trainstopsDB){
            command += 'global.remoteStopZones[\\"'+instanceID+'\\"] = {}';
            for(let trainstop in trainstopsDB[instanceID]){
                for(let sdi in trainstopsDB[instanceID][trainstop].stops) {
                    let stopdata = trainstopsDB[instanceID][trainstop].stops[sdi];
                    if(!stopdata.zones[0]) {
                        stopdata.zones = [];
                    }
                    command += 'global.remoteStopZones[\\"'+instanceID+'\\"][\\"'+this.doubleEscape(trainstop)+'\\"]={\\"' + stopdata.zones.join('\\",\\"') + '\\"}'
                }
            }
        }
        command += 'trainStopTrackingApi.rebuildInstanceLookup()';
        command += 'trainStopTrackingApi.rebuildRemoteZonestops()';

        command += '")';
        //console.log(command);
        this.messageInterface("/silent-command "+command);
    }
	async applyZonesDB(){
	    let data = {
	        event: "zones",
            zones: this.zonesDB
        };
        this.messageInterface('/silent-command remote.call("trainTeleports","json","' + this.singleEscape(JSON.stringify(data)) + '")');
    }
	async scriptOutput(data){
		if(data !== null){
			// this.messageInterface(data);

			if(data.substr(0,5) !== 'event') {
                this.socket.emit("trainteleport_json", JSON.parse(data));
            } else {
                let parsedData = {};
                data = data.split("|");
                data.forEach(kv => {
                    kv = kv.split(":");
                    parsedData[kv[0]] = kv[1];
                });
                this.messageInterface(JSON.stringify(parsedData));

                if (parsedData.event == "trainstop_added") {
                    this.messageInterface(`Adding trainstop ${parsedData.name} at x:${parsedData.x} y:${parsedData.y}`);
                    this.socket.emit("trainstop_added", parsedData);
                } else if (parsedData.event == "trainstop_edited") {
                    this.messageInterface(`Editing trainstop ${parsedData.name} at x:${parsedData.x} y:${parsedData.y}`);
                    this.socket.emit("trainstop_edited", parsedData);
                } else if (parsedData.event == "trainstop_removed") {
                    this.messageInterface(`Removing trainstop ${parsedData.name} at x:${parsedData.x} y:${parsedData.y}`);
                    this.socket.emit("trainstop_removed", parsedData);
                } else if (parsedData.event == "trainstop_blocked") {
                    this.messageInterface(`Blocking trainstop ${parsedData.name}`);
                    this.socket.emit("trainstop_blocked", parsedData);
                } else if (parsedData.event == "trainstop_unblocked") {
                    this.messageInterface(`Unblocking trainstop ${parsedData.name}`);
                    this.socket.emit("trainstop_unblocked", parsedData);
                } else if (parsedData.event == "getZones") {
                    this.messageInterface(`Requesting zones list`);
                    this.socket.emit("getZones", parsedData);
                } else if (parsedData.event == "getTrainstops") {
                    this.messageInterface(`Requesting trainstop list`);
                    this.socket.emit("getTrainstops", parsedData);
                } else if (parsedData.event) {
                    this.messageInterface(`Unknown event: ` + parsedData.event);
                }
            }
		}
	}
	async getSafeLua(filePath){
		return new Promise((resolve, reject) => {
			fs.readFile(filePath, "utf8", (err, contents) => {
				if(err){
					reject(err);
				} else {
                    // split content into lines
					contents = contents.split(/\r?\n/);

					// join those lines after making them save again
					contents = contents.reduce((acc, val) => {
                        val = val.replace(/\\/g ,'\\\\');
                        // remove leading and trailing spaces
					    val = val.trim();
                        // escape single quotes
					    val = val.replace(/'/g ,'\\\'');

					    // remove single line comments
                        let singleLineCommentPosition = val.indexOf("--");
                        let multiLineCommentPosition = val.indexOf("--[[");

						if(multiLineCommentPosition === -1 && singleLineCommentPosition !== -1) {
							val = val.substr(0, singleLineCommentPosition);
						}

                        return acc + val + '\\n';
					}, ""); // need the "" or it will not process the first row, potentially leaving a single line comment in that disables the whole code

					// console.log(contents);

					// this takes about 46 ms to minify train_stop_tracking.lua in my tests on an i3
					if(COMPRESS_LUA) contents = require("luamin").minify(contents);
					
					resolve(contents);
				}
			});
		});
	}
	async checkHotpatchInstallation(){
		let yn = await this.messageInterface("/silent-command if remote.interfaces['hotpatch'] then rcon.print('true') else rcon.print('false') end");
		yn = yn.replace(/(\r\n\t|\n|\r\t)/gm, "");
		if(yn == "true"){
			return true;
		} else if(yn == "false"){
			return false;
		}
	}
};
