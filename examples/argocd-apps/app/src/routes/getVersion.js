// Reports which build is running, so a rollout is visible in the browser and with curl.
module.exports = (req, res) => {
    res.send({
        version: process.env.APP_VERSION || 'dev',
        message: process.env.APP_MESSAGE || 'Hello from Kubewekend',
        hostname: require('os').hostname(),
    });
};
