const needle = require("needle");

let instances = {};

function getInstanceName(instanceID, config){
	return new Promise((resolve, reject) => {
		let instance = instances[instanceID];
		if(!instance){
			needle.get(config.masterIP+":"+config.masterPort+ '/api/slaves', (err, response) => {
				if(err || response.statusCode != 200) {
					console.log("Unable to get JSON master/api/slaves, master might be unaccessible");
				} else if (response && response.body) {	
					if(Buffer.isBuffer(response.body)) {console.log(response.body.toString("utf-8")); throw new Error();}
						try {
							for (let index in response.body)
								instances[index] = response.body[index].instanceName;
						} catch (e){
							console.log(e);
							return null;
						}
					instance = instances[instanceID] 							
					if (!instance) instance = instanceID;  //somehow the master doesn't know the instance	
					resolve(instance);
				}
			});
		} else {
			resolve(instance);
		}
	});
}


function getInstances(config){
    let fullinstances = {};

    return new Promise((resolve, reject) => {
		needle.get(config.masterIP+":"+config.masterPort+ '/api/slaves', (err, response) => {
			if(err || response.statusCode != 200) {
				console.log("Unable to get JSON master/api/slaves, master might be unaccessible");
			} else if (response && response.body) {
				if(Buffer.isBuffer(response.body)) {console.log(response.body.toString("utf-8")); throw new Error();}
				try {
				    // todo: only add them when they are "live"
					for (let index in response.body)
						fullinstances[index] = {
							publicIP: response.body[index].publicIP,
							serverPort: response.body[index].serverPort,
							instanceName: response.body[index].instanceName
						};
				} catch (e){
					console.log(e);
					return null;
				}
				resolve(fullinstances);
			}
		});
    });
}


module.exports = {
	getInstanceName,
    getInstances
};
