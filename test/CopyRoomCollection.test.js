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
        it("Owner can toggle whitelist", async function() {
            const enable_tx = await contract.setWhitelistOnlyMint(false);
            await enable_tx.wait();
            expect(await contract.whitelistOnlyMint()).to.be.false;

            const disable_tx = await contract.setWhitelistOnlyMint(true);
            await disable_tx.wait();
            expect(await contract.whitelistOnlyMint()).to.be.true;
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

    describe("Mint", function() {
        let mintBonusGroupId;

        it("Whitelisted user can mint single to new group", async function() {
            const EXPECTED_GID = ethers.BigNumber.from(1);
            const EXPECTED_NFT_ID = ethers.BigNumber.from(0);
            const tx = await contract.connect(signers.groupOwner).mintGroup(1, accounts.owner, 1, false);
            await tx.wait();
            expect(await contract.getLastGroupIdByOwner(accounts.groupOwner)).to.equal(EXPECTED_GID);

            const nft_members = await contract.getGroupMembers(EXPECTED_GID);
            expect(nft_members[0]).to.equal(EXPECTED_NFT_ID);
            expect(nft_members.length).to.equal(1);
        });
        it("Whitelisted user can mint multiple to new group", async function() {
            const EXPECTED_GID = ethers.BigNumber.from(2);
            const EXPECTED_NFT_ID = ethers.BigNumber.from(1);
            const tx = await contract.connect(signers.groupOwner).mintGroup(3, accounts.owner, 1, false);
            await tx.wait();
            expect(await contract.getLastGroupIdByOwner(accounts.groupOwner)).to.equal(EXPECTED_GID);

            const nft_members = await contract.getGroupMembers(EXPECTED_GID);
            expect(nft_members[0]).to.equal(EXPECTED_NFT_ID);
            expect(nft_members[1]).to.equal(EXPECTED_NFT_ID.add(1));
            expect(nft_members[2]).to.equal(EXPECTED_NFT_ID.add(2));
            expect(nft_members.length).to.equal(3);
        });
        it("Whitelisted user can mint multiple to existing group", async function() {
            const GROUP_ID = 1;
            const tx = await contract.connect(signers.groupOwner).mintToGroup(3, GROUP_ID, accounts.owner);
            await tx.wait();

            const nft_members = await contract.getGroupMembers(GROUP_ID);
            expect(nft_members.length).to.equal(4);
        });
        it("Mint fails if bonusOnMint is active and bank has insufficient funds", async function() {
            await expect(contract.connect(signers.groupOwner).mintGroup(10, accounts.owner, 100, true))
                .to.be.revertedWith("CopyRoom: Not enough ONE in bank");
        });
        it("Bonus correctly paid on mint and deposit made at time of mint", async function() {
             expect(await contract.connect(signers.groupOwner).mintGroup(1, accounts.owner, 100, true, {value: 100}))
                 .to.changeEtherBalance(accounts.owner, 100);
             const gid = await contract.getLastGroupIdByOwner(accounts.groupOwner);
             mintBonusGroupId = gid;
             const nfts = await contract.getGroupMembers(gid);
             expect(nfts.length).to.equal(1);
        });
        it("Transfer (not mint) bonus does not pay on mint", async function() {
            expect(await contract.connect(signers.groupOwner).mintGroup(1, accounts.owner, 100, false, {value: 100}))
                .to.changeEtherBalance(accounts.owner, 0);
            const gid = await contract.getLastGroupIdByOwner(accounts.groupOwner);
            const nfts = await contract.getGroupMembers(gid);
            expect(nfts.length).to.equal(1);
        });
        it("Can getOwnedGroupIds of user without groups", async function() {
            const gids = (await contract.getOwnedGroupIdsByOwner(accounts.owner))
                .filter((x) => x && x.toString() !== "0");

            expect(gids.length).to.equal(0);
        });
        it("Can getOwnedGroupIds of user with groups", async function() {
            const gids = (await contract.getOwnedGroupIdsByOwner(accounts.groupOwner))
                .filter((x) => x && x.toString() !== "0");

            expect(gids.length).to.equal(4);
        });
        it("Non group owner cannot disable mint bonus for existing group", async function() {
            await expect(contract.setActiveBonusForGroup(2, false))
                .to.be.revertedWith("CopyRoom: Insufficient permissions for group");
        });
        it("Group owner can disable mint bonus for existing group", async function() {
            expect(mintBonusGroupId).to.not.be.undefined;

            expect(await contract.isGroupBonusActive(mintBonusGroupId)).to.be.true;
            const tx = await contract.connect(signers.groupOwner).setActiveBonusForGroup(mintBonusGroupId, false);
            await tx.wait();
            expect(await contract.isGroupBonusActive(mintBonusGroupId)).to.be.false;
        });
    });

});
