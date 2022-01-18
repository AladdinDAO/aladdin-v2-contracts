/* eslint-disable node/no-missing-import */
import { AladdinHonor, Lottery, MockERC20 } from "../typechain";
import { MockContract } from "ethereum-waffle";
import { ethers, upgrades } from "hardhat";
import { deployMockForName } from "./mock";
import "./utils";
import { BigNumber, constants, Signer } from "ethers";
import { expect } from "chai";

describe("Lottery.spec", async () => {
  let deployer: Signer;
  let keeper: Signer;
  let alice: Signer;

  let ald: MockERC20;
  let nft: AladdinHonor;
  let lottery: Lottery;

  beforeEach(async () => {
    [deployer, keeper, alice] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20", deployer);
    ald = await MockERC20.deploy("ALD", "ALD", 18);
    await ald.deployed();

    const AladdinHonor = await ethers.getContractFactory("AladdinHonor", deployer);
    nft = await AladdinHonor.deploy();
    await nft.deployed();

    const Lottery = await ethers.getContractFactory("Lottery", deployer);
    lottery = (await upgrades.deployProxy(Lottery, [ald.address, nft.address])) as Lottery;

    await nft.setLottery(lottery.address);
    await lottery.updateKeeper(await keeper.getAddress());
  });

  context("nft utils", async () => {
    it("should revert, when non-owner setLevelURI", async () => {
      await expect(nft.connect(alice).setLevelURI(0, "")).to.revertedWith("Ownable: caller is not the owner");
    });

    it("should revert, when non-owner setLottery", async () => {
      await expect(nft.connect(alice).setLottery(constants.AddressZero)).to.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("should revert, when non-owner setPendingMints", async () => {
      await expect(nft.connect(alice).setPendingMints([], [])).to.revertedWith("Ownable: caller is not the owner");
    });

    it("should revert, when non-owner setPendingMint", async () => {
      await expect(nft.connect(alice).setPendingMint(constants.AddressZero, 1)).to.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    context("#setLevelURI", async () => {
      it("should revert, when level invalid", async () => {
        await expect(nft.setLevelURI(0, "")).to.revertedWith("AladdinHonor: invalid level");
        await expect(nft.setLevelURI(10, "")).to.revertedWith("AladdinHonor: invalid level");
      });

      it("should succeed", async () => {
        expect(await nft.levelToURI(1)).to.eq("");
        await nft.setLevelURI(1, "243");
        expect(await nft.levelToURI(1)).to.eq("243");
      });
    });

    context("#setLottery", async () => {
      it("should succeed", async () => {
        expect(await nft.lottery()).to.eq(lottery.address);
        await nft.setLottery(constants.AddressZero);
        expect(await nft.lottery()).to.eq(constants.AddressZero);
      });
    });

    context("#setPendingMints", async () => {
      it("should revert, when length mismatch", async () => {
        await expect(nft.setPendingMints([], [1])).to.revertedWith("AladdinHonor: length mismatch");
      });

      it("should revert, when level invalid", async () => {
        await expect(nft.setPendingMints([await alice.getAddress()], [0])).to.revertedWith(
          "AladdinHonor: invalid level"
        );
        await expect(nft.setPendingMints([await alice.getAddress()], [10])).to.revertedWith(
          "AladdinHonor: invalid level"
        );
      });

      it("should revert, when level already set", async () => {
        await nft.setPendingMints([await alice.getAddress()], [1]);
        await expect(nft.setPendingMints([await alice.getAddress()], [1])).to.revertedWith(
          "AladdinHonor: level already set"
        );
      });

      it("should succeed", async () => {
        await nft.setPendingMints([await alice.getAddress()], [1]);
        expect((await nft.addressToPendingMint(await alice.getAddress())).maxLevel).to.eq(BigNumber.from(1));
        await nft.setPendingMints([await alice.getAddress()], [9]);
        expect((await nft.addressToPendingMint(await alice.getAddress())).maxLevel).to.eq(BigNumber.from(9));
      });
    });

    context("#setPendingMint", async () => {
      it("should revert, when level invalid", async () => {
        await expect(nft.setPendingMint(await alice.getAddress(), 0)).to.revertedWith("AladdinHonor: invalid level");
        await expect(nft.setPendingMint(await alice.getAddress(), 10)).to.revertedWith("AladdinHonor: invalid level");
      });

      it("should revert, when level already set", async () => {
        await nft.setPendingMint(await alice.getAddress(), 1);
        await expect(nft.setPendingMint(await alice.getAddress(), 1)).to.revertedWith(
          "AladdinHonor: level already set"
        );
      });

      it("should succeed", async () => {
        await nft.setPendingMint(await alice.getAddress(), 1);
        expect((await nft.addressToPendingMint(await alice.getAddress())).maxLevel).to.eq(BigNumber.from(1));
        await nft.setPendingMint(await alice.getAddress(), 9);
        expect((await nft.addressToPendingMint(await alice.getAddress())).maxLevel).to.eq(BigNumber.from(9));
      });
    });

    context("#mint", async () => {
      it("should succeed", async () => {
        // await nft.setLottery(constants.AddressZero);
        await nft.setPendingMint(await alice.getAddress(), 4);
        expect(await nft.balanceOf(await alice.getAddress())).to.eq(constants.Zero);
        await nft.connect(alice).mint();
        expect(await nft.balanceOf(await alice.getAddress())).to.eq(BigNumber.from(4));
        await nft.setPendingMint(await alice.getAddress(), 8);
        await nft.connect(alice).mint();
        expect(await nft.balanceOf(await alice.getAddress())).to.eq(BigNumber.from(8));
      });
    });
  });

  context("lottery utils", async () => {
    it("should revert, when non-owner updateWeights", async () => {
      await expect(lottery.connect(alice).updateWeights([])).to.revertedWith("Ownable: caller is not the owner");
    });

    it("should revert, when non-owner updateParticipeThreshold", async () => {
      await expect(lottery.connect(alice).updateParticipeThreshold(1)).to.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("should revert, when non-owner updateTotalPrizeThreshold", async () => {
      await expect(lottery.connect(alice).updateTotalPrizeThreshold(1)).to.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("should revert, when non-owner updateKeeper", async () => {
      await expect(lottery.connect(alice).updateKeeper(constants.AddressZero)).to.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    context("#updateWeights", async () => {
      it("should revert, when length mismatch", async () => {
        await expect(lottery.updateWeights([])).to.revertedWith("Lottery: length mismatch");
      });

      it("should revert, when weight should increase", async () => {
        await expect(lottery.updateWeights([1, 0, 1, 0, 1, 0, 1, 0, 1])).to.revertedWith(
          "Lottery: weight should increase"
        );
      });

      it("should succeed", async () => {
        await lottery.updateWeights([1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(await lottery.weights(0)).to.eq(1);
        expect(await lottery.weights(1)).to.eq(2);
        expect(await lottery.weights(2)).to.eq(3);
        expect(await lottery.weights(3)).to.eq(4);
        expect(await lottery.weights(4)).to.eq(5);
        expect(await lottery.weights(5)).to.eq(6);
        expect(await lottery.weights(6)).to.eq(7);
        expect(await lottery.weights(7)).to.eq(8);
        expect(await lottery.weights(8)).to.eq(9);
      });
    });

    context("#updatePrizeInfo", async () => {
      it("should revert, when length mismatch", async () => {
        await expect(lottery.updatePrizeInfo([], [1, 2, 3, 4])).to.revertedWith("Lottery: length mismatch");
        await expect(lottery.updatePrizeInfo([1, 2, 3, 4], [])).to.revertedWith("Lottery: length mismatch");
      });

      it("should revert, when length mismatch", async () => {
        await expect(lottery.updatePrizeInfo([1, 2, 3, 4], [4, 3, 2, 1])).to.revertedWith("Lottery: sum mismatch");
      });

      it("should succeed", async () => {
        await lottery.updateTotalPrizeThreshold(20);
        await lottery.updatePrizeInfo([1, 2, 3, 4], [4, 3, 2, 1]);
        expect(await lottery.prizeInfo(0)).to.deep.eq([BigNumber.from(1), BigNumber.from(4)]);
        expect(await lottery.prizeInfo(1)).to.deep.eq([BigNumber.from(2), BigNumber.from(3)]);
        expect(await lottery.prizeInfo(2)).to.deep.eq([BigNumber.from(3), BigNumber.from(2)]);
        expect(await lottery.prizeInfo(3)).to.deep.eq([BigNumber.from(4), BigNumber.from(1)]);
      });
    });

    context("#openPrize", async () => {
      it("should revert, when non keeper call", async () => {
        await expect(lottery.openPrize()).to.revertedWith("Lottery: sender not allowed");
      });

      it("should revert, when pool size not enough", async () => {
        await lottery.updateKeeper(constants.AddressZero);
        await lottery.updateTotalPrizeThreshold(1);
        await expect(lottery.openPrize()).to.revertedWith("Lottery: not enough ald");
      });

      it("should succeed", async () => {
        await nft.setPendingMint(await alice.getAddress(), 8);
        await nft.connect(alice).mint();

        await lottery.updateWeights([1, 2, 3, 4, 5, 6, 7, 8, 9]);
        await lottery.updateTotalPrizeThreshold(11);
        await lottery.updateParticipeThreshold(1);
        await lottery.updatePrizeInfo([4, 3, 2, 1], [1, 1, 1, 2]);
        await ald.mint(lottery.address, 11);
        expect(await lottery.currentPoolSize()).to.eq(BigNumber.from(11));
        await lottery.connect(keeper).openPrize();
        expect(await lottery.currentPoolSize()).to.eq(BigNumber.from(0));

        expect(await lottery.unclaimedRewards(await alice.getAddress())).to.eq(BigNumber.from(11));
        expect(await lottery.totalUnclaimedRewards()).to.eq(BigNumber.from(11));

        await ald.mint(lottery.address, 20);
        expect(await lottery.currentPoolSize()).to.eq(BigNumber.from(20));

        await lottery.connect(alice).claim();
        expect(await ald.balanceOf(await alice.getAddress())).to.eq(BigNumber.from(11));
        expect(await lottery.unclaimedRewards(await alice.getAddress())).to.eq(BigNumber.from(0));
        expect(await lottery.totalUnclaimedRewards()).to.eq(BigNumber.from(0));
        expect(await lottery.currentPoolSize()).to.eq(BigNumber.from(20));

        console.log((await lottery.getAccountToWinInfo(await alice.getAddress())).toString());
      });
    });
  });
});
