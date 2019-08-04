const fs = require("fs");

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

            this.socket.on("transaction", async data => {
                let transaction = data.transactionId.split(":");
                let instanceId = transaction[0];
                let trainId = transaction[1];

                if(this.master.clients[instanceId]) {
                    this.master.clients[instanceId].socket.emit("transaction", {
                        event: "trainReceived",
                        trainId: trainId
                    });
                }
            });

            this.socket.on("trainteleport_json", async data => {
                if(data.event === 'teleportTrain') {
                	// got a train to deliver to one lucky node
                    data.transactionId = this.instanceID + ":" + data.localTrainid;
                    this.teleportTrain(data);
                } else if(data.event === 'zones') {
                	// got zones. store and tell the cluster
                    await this.setZones(data.zones)
                } else if(data.event === 'savezone') {
                    // zone got updated. store and tell the cluster
                    await this.addZone(data.zoneId, data.zone)
                } else if(data.event === 'removezone') {
                    // zone got removed. remove and tell the cluster
                    await this.removeZone(data.zoneId)
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



                } else if(data.event === 'trains') {
                    // console.log(data);
                    // got trains. store and tell the affected nodes
                    this.setTrains(data.trains)
                } else if(data.event === 'updateTrain') {
//                    console.log(data);
                    // train got updated. store and tell the affected nodes
                    this.updateTrain(data.trainId, data.train, data.oldTrainId1, data.oldTrainId2)
                } else if(data.event === 'removeTrain') {
//                    console.log(data);
                    // train got removed. remove and tell the affected nodes
                    this.removeTrain(data.trainId)
                } else {
                    console.log("UNKNOWN event" + data.event);
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
            trainstops[this.instanceID][name].stops = cleanStops;

			if(!trainstops[this.instanceID][name].stops[0]){
			    delete trainstops[this.instanceID][name];
                await this.master.propagateTrainstops();
			    return true;
            }
            await this.master.propagateTrainstops();
			return false;
		}
	}

	async setZones(instanceZones) {
        let zones = await this.master.getZones();

        if(instanceZones.length == 0) {
            instanceZones = [];
        }
        zones[this.instanceID] = instanceZones;
        await this.master.propagateZones();
    }
	async addZone(zoneIndex, zone){
		let zones = await this.master.getZones();

		if(!zones[this.instanceID][0]) {
            zones[this.instanceID] = [];
        }
		zones[this.instanceID][zoneIndex-1] = zone;
		await this.master.propagateZones();
    }
	async removeZone(zoneIndex){
        let zones = await this.master.getZones();
        delete zones[this.instanceID][zoneIndex-1];
        await this.master.propagateZones();
	}

	async setTrains(trains) {
        await this.master.setTrains(this.instanceID, trains);
    }
    async updateTrain(trainId, train) {
        await this.master.updateTrain(this.instanceID, trainId, train);
    }
    async removeTrain(trainId) {
        await this.master.removeTrain(this.instanceID, trainId);
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
		this.propagateZonesTimeout = null;
        this.trainstopsDatabase = {};

        this.trainDatabase = {};

        this.trainStopTrains = {};
        this.trainsKnownToInstances = {};


        // this.getTrainstops();

		this.io.on("connection", socket => {
		    this.socket = socket;

			socket.on("registerTrainTeleporter", data => {
				console.log("Registered train teleporter "+data.instanceID);

                this.trainstopsDatabase[data.instanceID] = {};

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

	clearInstanceTrains(instanceId) {
        for(let remoteInstanceId in this.trainsKnownToInstances) {
            let removedSomething = false;
            if (!this.trainsKnownToInstances[remoteInstanceId]) {
                this.trainsKnownToInstances[remoteInstanceId] = {};
            }

            if(this.trainsKnownToInstances[remoteInstanceId][instanceId]) {
                this.trainsKnownToInstances[remoteInstanceId][instanceId] = {};
                removedSomething = true;
            }

            for(let stopName in this.trainStopTrains[remoteInstanceId]) {
                if(this.trainStopTrains[remoteInstanceId][stopName][instanceId]) {
                    delete this.trainStopTrains[remoteInstanceId][stopName][instanceId];
                    removedSomething = true;
                }
            }


            if(removedSomething) {
                if(this.clients[remoteInstanceId]) {
                    this.clients[remoteInstanceId].socket.emit("trainDatabase", {
                        trainsKnownToInstances: this.trainsKnownToInstances[remoteInstanceId],
                        trainStopTrains: this.trainStopTrains[remoteInstanceId]
                    });
                }
            }
        }
    }

	addTrain(instanceId, trainId, train, propagate) {
        for(let remoteInstanceId in train.servers) {
            if(!this.trainsKnownToInstances[remoteInstanceId]) {
                this.trainsKnownToInstances[remoteInstanceId] = {};
            }
            if(!this.trainsKnownToInstances[remoteInstanceId][instanceId]) {
                this.trainsKnownToInstances[remoteInstanceId][instanceId] = {};
            }
            this.trainsKnownToInstances[remoteInstanceId][instanceId][trainId] = train;


            let stops = [];
            if(!this.trainStopTrains[remoteInstanceId]) {
                this.trainStopTrains[remoteInstanceId] = {};
            }
            for(let stopName in train.servers[remoteInstanceId]) {
                if(!this.trainStopTrains[remoteInstanceId][stopName]) {
                    this.trainStopTrains[remoteInstanceId][stopName] = {};
                }
                if(!this.trainStopTrains[remoteInstanceId][stopName][instanceId]) {
                    this.trainStopTrains[remoteInstanceId][stopName][instanceId] = {};
                }

                this.trainStopTrains[remoteInstanceId][stopName][instanceId][trainId] = trainId;
                stops.push(stopName);
            }

            if(propagate) {
                if(this.clients[remoteInstanceId]) {
                    this.clients[remoteInstanceId].socket.emit("addRemoteTrain", {
                        trainId: trainId,
                        train: train,
                        instanceId: instanceId,
                        stops: stops
                    });
                }

            }
        }
    }

	setTrains(instanceId, trains) {
        this.trainDatabase[instanceId] = trains;

        this.clearInstanceTrains(instanceId);

        for (let trainId in trains) {
            let train = trains[trainId];
            this.addTrain(instanceId, trainId, train, false);
        }

        for(let remoteInstanceId in this.trainsKnownToInstances) {
            if(this.clients[remoteInstanceId]) {
                this.clients[remoteInstanceId].socket.emit("trainDatabase", {
                    trainsKnownToInstances: this.trainsKnownToInstances[remoteInstanceId],
                    trainStopTrains: this.trainStopTrains[remoteInstanceId]
                });
            }
        }

    }

    updateTrain(instanceId, trainId, train) {
	    let found = false;
        for(let remoteInstanceId in this.trainsKnownToInstances) {
            if (this.trainsKnownToInstances[remoteInstanceId]
             && this.trainsKnownToInstances[remoteInstanceId][instanceId]
             && this.trainsKnownToInstances[remoteInstanceId][instanceId][trainId]) {

                this.trainsKnownToInstances[remoteInstanceId][instanceId][trainId] = train;
                found = true;

                if(this.clients[remoteInstanceId]) {
                    this.clients[remoteInstanceId].socket.emit("updateRemoteTrain", {
                        instanceId: instanceId,
                        trainId: trainId,
                        train: train
                    });
                }
            }
        }

        if(!found) {
            this.addTrain(instanceId, trainId, train, true);
        }
    }

    removeTrain(instanceId, trainId) {
        for(let remoteInstanceId in this.trainsKnownToInstances) {
            if (this.trainsKnownToInstances[remoteInstanceId]
             && this.trainsKnownToInstances[remoteInstanceId][instanceId]
             && this.trainsKnownToInstances[remoteInstanceId][instanceId][trainId]) {

                let stops = [];
                for (let stopName in this.trainStopTrains[remoteInstanceId]) {
                    if(this.trainStopTrains[remoteInstanceId][stopName][instanceId][trainId]) {
                        delete this.trainStopTrains[remoteInstanceId][stopName][instanceId][trainId];

                        console.log("L1:" + Object.keys(this.trainStopTrains[remoteInstanceId][stopName][instanceId]).length);
                        if(Object.keys(this.trainStopTrains[remoteInstanceId][stopName][instanceId]).length == 0) {
                            delete this.trainStopTrains[remoteInstanceId][stopName][instanceId]
                        }
                        console.log("L2:" + Object.keys(this.trainStopTrains[remoteInstanceId][stopName]).length);
                        if(Object.keys(this.trainStopTrains[remoteInstanceId][stopName]).length == 0) {
                            delete this.trainStopTrains[remoteInstanceId][stopName]
                        }

                        console.log(this.trainStopTrains[remoteInstanceId]);
                        stops.push(stopName);
                    }
                }
                delete this.trainsKnownToInstances[remoteInstanceId][instanceId][trainId];

                if(this.clients[remoteInstanceId]) {
                    // for now send the whole db, fix later
                    this.clients[remoteInstanceId].socket.emit("trainDatabase", {
                        trainsKnownToInstances: this.trainsKnownToInstances[remoteInstanceId],
                        trainStopTrains: this.trainStopTrains[remoteInstanceId]
                    });

                    this.clients[remoteInstanceId].socket.emit("removeRemoteTrain", {
                        instanceId: instanceId,
                        trainId: trainId,
                        stops: stops
                    });
                } else {
                    console.log("train for removal not found")
                }
            }
        }
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
            this.io.sockets.emit("trainstopsDatabase", this.trainstopsDatabase);
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
//console.log("ZONES:", JSON.stringify(this.zonesDatabase));
            this.io.sockets.emit("zonesDatabase", this.zonesDatabase);
            this.io.sockets.emit("initAllTrains");


        }, 100);
    }

}
module.exports = masterPlugin;
