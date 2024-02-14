// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTMarketplace {
    struct Bid {
        address payable buyer;
        uint amount;
    }

    struct Auction {
        address seller;
        address nftAddress;
        uint tokenId;
        uint minPrice;
        uint bestBid;
        Bid[] bids;
        uint deadline;
    }

    mapping(bytes32 => Auction) public auctions;

    event NewAuction(
        address indexed seller,
        address indexed nftAddress,
        uint tokenId,
        uint minPrice,
        uint deadline
    );

    event NewBid(
        bytes32 indexed auctionId,
        address indexed buyer,
        uint amount
    );

    event NewTransaction(
        address indexed seller,
        address indexed buyer,
        address indexed nftAddress,
        uint tokenId,
        uint price
    );

    error BadDeadline();
    error AuctionExpired();
    error AuctionNotFound();
    error BidTooLow();
    error DeadlineNotReached();

    function openAuction(
        address nftAddress,
        uint tokenId,
        uint minPrice,
        uint deadline
    ) external {
        IERC721 nft = IERC721(nftAddress);
        nft.transferFrom(msg.sender, address(this), tokenId);

        if(deadline < block.timestamp + 86400) {
          revert BadDeadline();
        }

        bytes32 auctionId = keccak256(abi.encode(nft, tokenId));

        auctions[auctionId].seller = msg.sender;
        auctions[auctionId].nftAddress = nftAddress;
        auctions[auctionId].tokenId = tokenId;
        auctions[auctionId].minPrice = minPrice;
        auctions[auctionId].deadline = deadline;

        emit NewAuction(
            msg.sender,
            nftAddress,
            tokenId,
            minPrice,
            deadline
        );
    }

    function bid(bytes32 auctionId) external payable {
        Auction storage auction = auctions[auctionId];
        IERC721 nft = IERC721(auction.nftAddress);

        if(auction.seller == address(0)) {
          revert AuctionNotFound();
        }
        if(auction.deadline < block.timestamp) {
          revert AuctionExpired();
        }
        if(msg.value <= auction.bestBid) {
          revert BidTooLow();
        }

        if (auction.minPrice > 0 && msg.value >= auction.minPrice) {
            auction.seller.call{value: msg.value}("");
            nft.transferFrom(address(this), msg.sender, auction.tokenId);
            for (uint i = 0; i < auction.bids.length; i++) {
                if (auction.bids[i].buyer != msg.sender) {
                    auction.bids[i].buyer.call{value: auction.bids[i].amount}(
                        ""
                    );
                }
            }
            emit NewTransaction(
                auction.seller,
                msg.sender,
                auction.nftAddress,
                auction.tokenId,
                msg.value
            );
            delete auctions[auctionId];
            return;
        }

        auction.bids.push(
            Bid({buyer: payable(msg.sender), amount: msg.value})
        );
        auction.bestBid = msg.value;
        emit NewBid(auctionId, msg.sender, msg.value);
    }

    function closeAuction(bytes32 auctionId) external {
        Auction storage auction = auctions[auctionId];
        IERC721 nft = IERC721(auction.nftAddress);

        if(auction.seller == address(0)) {
          revert AuctionNotFound();
        }
        if(auction.deadline >= block.timestamp) {
          revert DeadlineNotReached();
        }

        if(auction.bids.length == 0) {
            nft.transferFrom(address(this), auction.seller, auction.tokenId);
            return;
        } 

        if(auction.minPrice > 0) {
            Bid storage bestBid = auction.bids[auction.bids.length - 1];
            for (uint i = 0; i < auction.bids.length; i++) {
                auction.bids[i].buyer.call{value: auction.bids[i].amount}("");
            }
            nft.transferFrom(address(this), auction.seller, auction.tokenId);
            return;
        }

        if(auction.minPrice == 0) {
            Bid storage bestBid = auction.bids[auction.bids.length - 1];
            for (uint i = 0; i < auction.bids.length; i++) {
                if (auction.bids[i].buyer != bestBid.buyer) {
                    auction.bids[i].buyer.call{value: auction.bids[i].amount}("");
                }
            }
            nft.transferFrom(address(this), bestBid.buyer, auction.tokenId);
            auction.seller.call{value: bestBid.amount}("");
        }
    }
}