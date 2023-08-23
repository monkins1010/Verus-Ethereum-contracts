require('dotenv').config();
const spawn = require('child_process').spawn;

// Main function to start ganache-cli with the specified account
function startGanacheWithAccount(privateKey) {
  const formattedPrivateKey = `0x${privateKey}`;

  // Use spawn to run ganache-cli with the --account option
  const ganacheProcess = spawn('ganache-cli', [
    '-l', '1500000000',
    '--account', `${formattedPrivateKey},100000000000000000000` // private key, initial balance in wei
  ]);

  ganacheProcess.stdout.on('data', (data) => {
   // console.log(data.toString());
  });

  ganacheProcess.stderr.on('data', (data) => {
    console.error(data.toString());
  });

  ganacheProcess.on('close', (code) => {
   // console.log(`ganache-cli process exited with code ${code}`);
  });

  return ganacheProcess;
}

function runTruffleTests() {
  const truffleProcess = spawn('truffle', ['test']);

  truffleProcess.stdout.on('data', (data) => {
    console.log(data.toString());
  });

  truffleProcess.stderr.on('data', (data) => {
    console.error(data.toString());
  });

  truffleProcess.on('close', (code) => {
 //   console.log(`Truffle tests process exited with code ${code}`);
    setTimeout(() => {
      process.exit(0); // Exit Node.js process after 2 seconds
    }, 2000);
  });
}

// Start ganache-cli with the specified account
const ganacheProcess = startGanacheWithAccount(process.env.GANACHE_KEY);

ganacheProcess.stdout.on('data', (data) => {
  if (data.toString().includes('Listening on')) {
    runTruffleTests();
  }
});
