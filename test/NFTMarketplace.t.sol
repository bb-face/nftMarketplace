// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/NFTMarketplace.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint tokenId) public {
        _mint(to, tokenId);
    }
}

contract NFTMarketplaceTest is Test {
    NFTMarketplace public marketplace;
    MockNFT public nft;
    uint public tokenId;
    bytes32 public auctionId;
    address public seller;
    address public buyer1;
    address public buyer2;
    uint public minPrice;
    uint public deadline;
    uint public buyersInitialBalance;

    function setUp() public {
        marketplace = new NFTMarketplace();
        nft = new MockNFT();
        tokenId = 1;
        auctionId = keccak256(abi.encode(address(nft), tokenId));
        minPrice = 1 ether;
        deadline = block.timestamp + 1 days;

        seller = makeAddr("Seller");
        nft.mint(seller, tokenId);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);

        buyer1 = makeAddr("Buyer");
        buyer2 = makeAddr("Buyer 2");
        buyersInitialBalance = 10 ether;
        vm.deal(buyer1, buyersInitialBalance);
        vm.deal(buyer2, buyersInitialBalance);
    }

    function test__OpenAuctionSucceeds() public {
        vm.startPrank(seller);

        vm.expectEmit();
        emit NFTMarketplace.NewAuction(
            seller,
            address(nft),
            tokenId,
            minPrice,
            deadline
        );
        marketplace.openAuction(address(nft), 1, minPrice, deadline);

        (
            address storedSeller,
            address storedNftAddress,
            uint storedTokenId,
            uint storedMinPrice,
            uint storedBestBid,
            uint storedDeadline
        ) = marketplace.auctions(keccak256(abi.encode(address(nft), tokenId)));
        assertEq(storedSeller, seller);
        assertEq(storedNftAddress, address(nft));
        assertEq(storedTokenId, tokenId);
        assertEq(storedMinPrice, minPrice);
        assertEq(storedBestBid, 0);
        assertEq(storedDeadline, deadline);
    }

    function test__OpenAuctionFailsWhenDeadlineNotInRange() public {
        deadline = 1;
        vm.startPrank(seller);

        vm.expectRevert(NFTMarketplace.BadDeadline.selector);
        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);
    }

    function test__BidSucceedsWhenBelowMinPrice() public {
        uint bidAmount = minPrice - 1;
        vm.prank(seller);
        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        vm.expectEmit();
        emit NFTMarketplace.NewBid(auctionId, buyer1, bidAmount);
        marketplace.bid{value: bidAmount}(auctionId);
        uint balance = address(marketplace).balance;
        address nftOwner = nft.ownerOf(tokenId);
        assertEq(balance, bidAmount);
        assertEq(nftOwner, address(marketplace));
    }

    function test__BidSucceedsWhenBidAtOrAboveMinPrice() public {
        uint bidAmount = minPrice;
        vm.prank(seller);
        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        vm.expectEmit();
        emit NFTMarketplace.NewTransaction(
            seller,
            buyer1,
            address(nft),
            tokenId,
            bidAmount
        );
        marketplace.bid{value: bidAmount}(auctionId);
        uint balance = seller.balance;
        address nftOwner = nft.ownerOf(tokenId);
        assertEq(balance, bidAmount);
        assertEq(nftOwner, buyer1);
    }

    function test__BidFailsWhenAuctionNotFound() public {
        uint bidAmount = 1;
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        skip(deadline);
        vm.prank(buyer1);
        vm.expectRevert(NFTMarketplace.AuctionNotFound.selector);
        marketplace.bid{value: bidAmount}(bytes32(0));
    }

    function test__BidFailsWhenAuctionExpired() public {
        minPrice = 0;
        uint bidAmount = 1;
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        skip(deadline);
        vm.prank(buyer1);
        vm.expectRevert(NFTMarketplace.AuctionExpired.selector);
        marketplace.bid{value: bidAmount}(auctionId);
    }

    function test__BidFailsWhenBelowBestBid() public {
        uint bidAmount = 1;
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        marketplace.bid{value: bidAmount}(auctionId);

        vm.prank(buyer2);
        vm.expectRevert(NFTMarketplace.BidTooLow.selector);
        marketplace.bid{value: bidAmount}(auctionId);
    }

    function test__CloseAuctionSucceedsWhenNoBid() public {
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);
        skip(deadline);
        marketplace.closeAuction(auctionId);
        address nftOwner = nft.ownerOf(tokenId);
        assertEq(nftOwner, seller);
    }

    function test__CloseAuctionSucceedsWhenMinPriceIsAboveZero() public {
        uint bidAmount = 1;

        vm.prank(seller);
        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        marketplace.bid{value: bidAmount}(auctionId);

        skip(deadline);
        marketplace.closeAuction(auctionId);
        uint balance = buyer1.balance;
        address nftOwner = nft.ownerOf(tokenId);
        assertEq(balance, buyersInitialBalance);
        assertEq(nftOwner, seller);
    }

    function test__CloseAuctionSucceedsWhenMinPriceIsZero() public {
        minPrice = 0;
        uint bidAmount = 1;

        vm.prank(seller);
        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        marketplace.bid{value: bidAmount}(auctionId);

        skip(deadline);
        marketplace.closeAuction(auctionId);
        uint balance = seller.balance;
        address nftOwner = nft.ownerOf(tokenId);
        assertEq(balance, bidAmount);
        assertEq(nftOwner, buyer1);
    }

    function test__CloseAuctionFailsWhenAuctionDoesntExist() public {
        uint bidAmount = 1;
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        marketplace.bid{value: bidAmount}(auctionId);

        vm.expectRevert(NFTMarketplace.AuctionNotFound.selector);
        marketplace.closeAuction(bytes32(0));
    }

    function test__CloseAuctionFailsWhenDeadlineNotReached() public {
        uint bidAmount = 1;
        vm.prank(seller);

        marketplace.openAuction(address(nft), tokenId, minPrice, deadline);

        vm.prank(buyer1);
        marketplace.bid{value: bidAmount}(auctionId);

        vm.expectRevert(NFTMarketplace.DeadlineNotReached.selector);
        marketplace.closeAuction(auctionId);
    }
}
