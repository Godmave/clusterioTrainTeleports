const fs = require("fs");
const changesets = require("diff-json");

class trainTeleporter{
	constructor({socket, instanceID, master}){
		this.socket = socket;
		this.instanceID = instanceID;
		this.master = master;

		(async () => {
		    /*
			this.socket.on("getTrainstops", async () => {
				this.socket.emit("trainstopsDatabase", await this.master.getTrainstops());
			});
			*/
			this.socket.on("trainstop_added", async data => {
				await this.addTrainstop(data);
				console.log("trainstop_added: "+data.name + " for instance: " + this.instanceID);
			});
			this.socket.on("trainstop_edited", async data => {
				await this.removeTrainstop({
					x:data.x,
					y:data.y,
					s:data.s,
					name:data.oldName
				});
				await this.addTrainstop(data);
				console.log("trainstop_edited: "+data.name + " for instance: " + this.instanceID);
			});
			this.socket.on("trainstop_removed", async data => {
				await this.removeTrainstop(data);
				console.log("trainstop_removed: "+data.name + " for instance: " + this.instanceID);
			});
            this.socket.on("trainstop_blocked", async data => {
                this.master.io.sockets.emit("trainstop_blocked", data);
                console.log("trainstop_blocked: "+data.name);
            });
            this.socket.on("trainstop_unblocked", async data => {
                this.master.io.sockets.emit("trainstop_unblocked", data);
                console.log("trainstop_unblocked: "+data.name);
            });

            this.socket.on("trainteleport_json", async data => {
                if(data.event === 'teleportTrain') {
                	// got a train to deliver to one lucky node
                    this.teleportTrain(data);
                } else if(data.event === 'zones') {
                	// got zones. store and tell the cluster
                    this.setZones(data.zones)
                } else if(data.event === 'savezone') {
                    // zone got updated. store and tell the cluster
                    this.addZone(data.zoneId, data.zone)
                } else if(data.event === 'removezone') {
                    // zone got removed. remove and tell the cluster
                    this.removeZone(data.zoneId)
                } else if(data.event === 'addStop') {
                    await this.addTrainstop(data.stop);
                } else if(data.event === 'updateStop') {
                    let lastOfHisKind = await this.removeTrainstop({
                        x:data.stop.x,
                        y:data.stop.y,
                        surface:data.stop.surface,
                        name:data.stop.oldName
                    });

                    if(lastOfHisKind) {
                        this.master.io.sockets.emit("trainStopRenameSchedules", {
                            instanceID: this.instanceID,
                            oldName: data.stop.oldName,
                            name: data.stop.name
                        });
                    }

                    await this.addTrainstop(data.stop);
                }
            });
        })();
	}
	async teleportTrain(data) {
	    // just forward the event
        if(this.master.clients[data['destinationInstanceId']]) {
            this.master.clients[data['destinationInstanceId']].socket.emit("trainteleport_json", data);
        } else {
            console.log("Got no valid socket for " + data['destinationInstanceId'] + " at the moment");
        }
    }

	async addTrainstop({x, y, surface, name, zones}){
		let trainstops = await this.master.getTrainstops();
		if(!trainstops[this.instanceID]) trainstops[this.instanceID] = {};
		if(!trainstops[this.instanceID][name]) trainstops[this.instanceID][name] = {name, stops:[]};
		trainstops[this.instanceID][name].stops.push({x,y,surface,zones});
		
		await this.master.propagateTrainstops();
		return true;
	}
	async removeTrainstop({x, y, surface, name}){
		let trainstops = await this.master.getTrainstops();
		if(!trainstops[this.instanceID][name]){
		    console.log("not found\n");
			return true;
		} else {
			var cleanStops = [];
			trainstops[this.instanceID][name].stops.forEach((trainstop, index) => {
				if(trainstop.x != x || trainstop.y != y || trainstop.surface != surface){
					cleanStops.push(trainstop);
				}
			});
			console.log("--------------\n");
            console.log(name, cleanStops);
            console.log("--------------\n");
            trainstops[this.instanceID][name].stops = cleanStops;

			if(!trainstops[this.instanceID][name].stops[0]) delete trainstops[this.instanceID][name];
            await this.master.propagateTrainstops();
			return true;
		}
	}

	async setZones(instanceZones) {
        let zones = await this.master.getZones();
        zones[this.instanceID] = instanceZones;
        await this.master.propagateZones();
    }
	async addZone(zoneIndex, zone){
		let zones = await this.master.getZones();
        zoneIndex = zoneIndex - 1;

		if(!zones[this.instanceID]) zones[this.instanceID] = {};
		zones[this.instanceID][zoneIndex] = zone;
		await this.master.propagateZones();
	}
	async removeZone(zoneIndex){
        let zones = await this.master.getZones();
        delete zones[this.instanceID][zoneIndex-1];
        await this.master.propagateZones();
	}
}

class masterPlugin {
	constructor({config, pluginConfig, path, socketio, express}){
		this.config = config;
		this.pluginConfig = pluginConfig;
		this.pluginPath = path;
		this.io = socketio;
		this.express = express;
		
		this.clients = {};
		this.socket = null;
		this.propagateStopsTimeout = null;
		this.lastPropagatedTrainstops = null;
		this.propagateZonesTimeout = null;
		this.lastPropagatedZones = null;
        this.trainstopsDatabase = {};

        this.getTrainstops();

		this.io.on("connection", socket => {
		    this.socket = socket;

			socket.on("registerTrainTeleporter", data => {
				console.log("Registered train teleporter "+data.instanceID);
				this.clients[data.instanceID] = new trainTeleporter({
					master:this,
					instanceID: data.instanceID,
					socket,
				});
				socket.emit("trainTeleporter_registered", {status:"ok"});
				socket.emit("trainstopsDatabase", this.trainstopsDatabase);
				socket.emit("zonesDatabase", this.zonesDatabase);
			});

            socket.on("disconnect", data => {
                for(let id in this.clients) {
                    if(this.clients[id].socket.id == socket.id) {
                        console.log("Lost connection to instance: " + id);
                        console.log("Removing its trainstops");

                        delete this.trainstopsDatabase[id];
                        this.propagateTrainstops();

                        console.log("Removing its zones");
                        if(this.zonesDatabase && this.zonesDatabase[id]) {
                            delete this.zonesDatabase[id];
                            this.propagateZones();
                        }
                        break;
                    }
                }
            });

		});
		
		this.express.get("/api/trainTeleports/getTrainstops", async (req,res) => {
			res.send(await this.getTrainstops());
		});
		this.express.get("/api/trainTeleports/getZones", async (req,res) => {
			res.send(await this.getZones());
		});
	}
    getTrainstops(){
        return new Promise((resolve) => {
            if(!this.trainstopsDatabase){
                this.trainstopsDatabase = {};
            }
            resolve(this.trainstopsDatabase);
        });
    }
    propagateTrainstops() {
	    if(this.propagateStopsTimeout) {
	        clearTimeout(this.propagateStopsTimeout);
        }
	    this.propagateStopsTimeout = setTimeout(() => {
console.log(JSON.stringify(this.trainstopsDatabase));
            if(!this.lastPropagatedTrainstops) {
                this.lastPropagatedTrainstops = JSON.parse(JSON.stringify(this.trainstopsDatabase));
                this.io.sockets.emit("trainstopsDatabase", this.trainstopsDatabase);
            } else {
                let diff = changesets.diff(this.lastPropagatedTrainstops, this.trainstopsDatabase);
                this.io.sockets.emit("trainstopsDatabaseDiff", diff);
//console.log(JSON.stringify(diff));
                this.lastPropagatedTrainstops = JSON.parse(JSON.stringify(this.trainstopsDatabase));
            }

        }, 100);
    }
    getZones(){
        return new Promise((resolve) => {
            if(!this.zonesDatabase){
                this.zonesDatabase = {};
            }
            resolve(this.zonesDatabase);
        });
    }
    propagateZones() {
        if(this.propagateZonesTimeout) {
            clearTimeout(this.propagateZonesTimeout);
        }
        this.propagateZonesTimeout = setTimeout(() => {
console.log(JSON.stringify(this.zonesDatabase));
            if(!this.lastPropagatedZones) {
                this.lastPropagatedZones = JSON.parse(JSON.stringify(this.zonesDatabase));
                this.io.sockets.emit("zonesDatabase", this.zonesDatabase);
            } else {
                let diff = changesets.diff(this.lastPropagatedZones, this.zonesDatabase);
                if(diff) {
                    this.io.sockets.emit("zonesDatabaseDiff", diff);
// console.log(JSON.stringify(diff));
                    this.lastPropagatedZones = JSON.parse(JSON.stringify(this.zonesDatabase));
                }
            }

        }, 100);
    }

}
module.exports = masterPlugin;
