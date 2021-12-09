async function main() {
    // Deploy YandaToken
    const Token = await ethers.getContractFactory("YandaToken");
    const token = await Token.deploy();
    // Deploy YandaGovernor with YandaToken address as argument
    const Governor = await ethers.getContractFactory("YandaGovernor");
    const governor = await Governor.deploy(token.address);

    console.log("YandaToken deployed at:", token.address);
    console.log("YandaGovernor deployed at:", governor.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
