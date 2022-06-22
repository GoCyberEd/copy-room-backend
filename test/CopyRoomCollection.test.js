const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CopyRoomCollection", function () {
    let contract;
    let signers = {};
    let accounts = {}

    before(async () => {
        const CopyRoomCollection = await ethers.getContractFactory("CopyRoomCollection");
        contract = await CopyRoomCollection.deploy("CopyRoom", "CPY");
        await contract.deployed();

        const [owner, groupOwner, randomUser] = await ethers.getSigners();
        signers = { owner, groupOwner, randomUser };
        accounts = {
            owner: await owner.getAddress(),
            groupOwner: await groupOwner.getAddress(),
            randomUser: await randomUser.getAddress(),
        };
    });

    describe("Whitelist", function() {
        it("Should be whitelisted on deployment", async function () {
            expect(await contract.whitelistOnlyMint()).to.equal(true);
        });
        it("Non-owner cannot toggle whitelist", async function() {
            await expect(contract.connect(accounts.randomUser).setWhitelistOnlyMint(true)).to.be.reverted;
        });
        it("Non-owner cannot modify whitelisted addresses", async function() {
            await expect(contract.connect(accounts.randomUser).setMintWhitelistForAccounts([accounts.groupOwner], true))
                .to.be.reverted;
            expect(await contract.getMintWhitelistStatusForAccount(accounts.groupOwner)).to.equal(false);
        });
        it("Owner can add to whitelist", async function() {
            expect(await contract.getMintWhitelistStatusForAccount(accounts.groupOwner)).to.equal(false);
            const tx = await contract.setMintWhitelistForAccounts([accounts.groupOwner], true);
            await tx.wait();
            expect(await contract.getMintWhitelistStatusForAccount(accounts.groupOwner)).to.equal(true);
        });
    });

    describe("Bank", function() {
        it("Can deposit to own bank", async function() {
            expect(await contract.getOneBankValue(accounts.owner)).to.equal(0);
            await (await contract.depositOneToMyBank({ value: 1 })).wait();
            expect(await contract.getOneBankValue(accounts.owner)).to.equal(ethers.BigNumber.from(1));
        });
        it("Can deposit to another's bank", async function() {
            expect(await contract.getOneBankValue(accounts.groupOwner)).to.equal(0);
            await (await contract.depositOneToBank(accounts.groupOwner, { value: 2 })).wait();
            expect(await contract.getOneBankValue(accounts.groupOwner)).to.equal(ethers.BigNumber.from(2));
            expect(await contract.getOneBankValue(accounts.owner)).to.equal(ethers.BigNumber.from(1));
        });
        it("Cannot withdraw more than bank amount", async function() {
            expect(contract.withdrawOneFromMyBank(2)).to.be.revertedWith("CopyRoom: Not enough ONE in bank");
        });
        it("Can increase bank by sending to contract", async function() {
            expect(await contract.getOneBankValue(accounts.owner)).to.equal(1);
            await signers.owner.sendTransaction({
                to: contract.address,
                value: ethers.BigNumber.from(2),
            });
            expect(await contract.getOneBankValue(accounts.owner)).to.equal(ethers.BigNumber.from(3));
        });
        it("Can withdraw all from own bank", async function() {
            expect(await contract.withdrawOneFromMyBank(3)).to.changeEtherBalance(accounts.owner, 3);
        });
    });

});
