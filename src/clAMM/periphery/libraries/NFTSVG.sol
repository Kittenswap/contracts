// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;

import "../../core/libraries/TickMath.sol";
import "openzeppelin-contracts-v3.4.2/contracts/utils/Strings.sol";
import "openzeppelin-contracts-v3.4.2/contracts/math/SafeMath.sol";
import "base64-sol/base64.sol";

/// @title NFTSVG
/// @notice Provides a function for generating an SVG associated with a CL NFT
library NFTSVG {
    using Strings for uint256;
    using SafeMath for uint256;

    function generateSVG(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        uint256 quoteTokensOwed,
        uint256 baseTokensOwed,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) public pure returns (string memory svg) {
        return
            string(
                abi.encodePacked(
                    '<svg width="800" height="800" viewBox="0 0 800 800" fill="none" xmlns="http://www.w3.org/2000/svg">',
                    '<g id="NFT Kitten" clip-path="url(#clip0_1098_820)">',
                    '<rect width="800" height="800" fill="#252525"/>',
                    '<g id="shadow">',
                    '<g id="Group 465">',
                    '<path id="Rectangle 173" d="M394 234L394 566L-0.000117372 566L-0.00012207 234L394 234Z" fill="url(#paint0_linear_1098_820)"/>',
                    "</g>",
                    "</g>",
                    generateTopText({
                        quoteTokenSymbol: quoteTokenSymbol,
                        baseTokenSymbol: baseTokenSymbol,
                        tokenId: tokenId,
                        tickSpacing: tickSpacing
                    }),
                    generateArt(),
                    generateBottomText({
                        quoteTokenSymbol: quoteTokenSymbol,
                        baseTokenSymbol: baseTokenSymbol,
                        quoteTokensOwed: quoteTokensOwed,
                        baseTokensOwed: baseTokensOwed,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        quoteTokenDecimals: quoteTokenDecimals,
                        baseTokenDecimals: baseTokenDecimals
                    }),
                    generateSVGDefs(),
                    "</svg>"
                )
            );
    }

    function generateTopText(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        uint256 tokenId,
        int24 tickSpacing
    ) private pure returns (string memory svg) {
        string memory poolId = string(
            abi.encodePacked(
                "CL",
                tickToString(tickSpacing),
                "-",
                quoteTokenSymbol,
                "/",
                baseTokenSymbol
            )
        );
        string memory tokenIdStr = string(
            abi.encodePacked("ID #", tokenId.toString())
        );
        string memory id = string(abi.encodePacked(poolId, tokenIdStr));
        svg = string(
            abi.encodePacked(
                '<g id="',
                id,
                '">',
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="32" font-weight="bold" letter-spacing="0em"><tspan x="56" y="85.5938">',
                poolId,
                "</tspan></text>",
                "</g>",
                '<text id="ID #1223" fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em">',
                '<tspan x="56" y="128.913">',
                tokenIdStr,
                "</tspan>",
                "</text>"
            )
        );
    }

    function generateArt() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<circle id="circle" cx="400" cy="400" r="166" fill="black"/>',
                '<g id="kitten" transform="translate(0, 20)">',
                '<path d="M294 379.746V409.746H300.228V397.964L311.512 409.746H320.001L305.899 395.167L318.944 379.746H310.74L300.228 392.223V379.746H294Z" fill="#00FF00"/>',
                '<path d="M330 379.746V409.746H336.228V379.746H330Z" fill="#00FF00"/>',
                '<path d="M345 379.746V385.194H357.229V409.746H363.457V385.194H375.685V379.746H345Z" fill="#00FF00"/>',
                '<path d="M385 379.746V385.194H397.229V409.746H403.457V385.194H415.685V379.746H385Z" fill="#00FF00"/>',
                '<path d="M425 379.746V409.746H450.599V404.299H431.228V397.561H447.142V392.112H431.228V385.194H450.599V379.746H425Z" fill="#00FF00"/>',
                '<path d="M460 379.746V409.746H466.228V389.07L486.37 409.746H492.599V379.746H486.37V400.423L466.228 379.746H460Z" fill="#00FF00"/>'
            )
        );
    }

    function generateSVGDefs() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                "<defs>",
                '<linearGradient id="paint0_linear_1098_820" x1="491" y1="566" x2="26.2101" y2="566" gradientUnits="userSpaceOnUse">'
                '<stop offset="0.142" stop-color="white" stop-opacity="0.2"/>',
                '<stop offset="1" stop-opacity="0"/>',
                "</linearGradient>",
                '<clipPath id="clip0_1098_820">',
                '<rect width="800" height="800" fill="white"/>',
                "</clipPath>",
                "</defs>"
            )
        );
    }

    function generateBottomText(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        uint256 quoteTokensOwed,
        uint256 baseTokensOwed,
        int24 tickLower,
        int24 tickUpper,
        uint8 quoteTokenDecimals,
        uint8 baseTokenDecimals
    ) internal pure returns (string memory svg) {
        string memory balance0 = balanceToDecimals(
            quoteTokensOwed,
            quoteTokenDecimals
        );
        string memory balance1 = balanceToDecimals(
            baseTokensOwed,
            baseTokenDecimals
        );
        string memory balances = string(
            abi.encodePacked(
                balance0,
                " ",
                quoteTokenSymbol,
                " ~ ",
                balance1,
                " ",
                baseTokenSymbol
            )
        );
        string memory tickLow = string(
            abi.encodePacked(tickToString(tickLower), " Low ")
        );
        string memory tickHigh = string(
            abi.encodePacked(tickToString(tickUpper), " High ")
        );
        svg = string(
            abi.encodePacked(
                '<text id="',
                balances,
                '" fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="32" font-weight="bold" letter-spacing="0em"><tspan x="56" y="676.594">',
                balances,
                "</tspan></text>",
                '<rect id="line" opacity="0.05" x="56" y="700" width="693" height="2" fill="#D9D9D9"/>',
                '<text id="',
                tickLow,
                "&#226;&#128;&#148; ",
                tickHigh,
                '" fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em"><tspan x="56" y="736.434">',
                tickLow,
                "&#x2014; ",
                tickHigh,
                "</tspan></text>",
                "</g>"
            )
        );
    }

    function balanceToDecimals(
        uint256 balance,
        uint8 decimals
    ) private pure returns (string memory) {
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = balance / divisor;
        uint256 fractionalPart = balance % divisor;

        // trim to 5 dp
        if (decimals > 5) {
            uint256 adjustedDivisor = 10 ** (decimals - 5);
            fractionalPart = adjustedDivisor > 0
                ? fractionalPart / adjustedDivisor
                : fractionalPart;
        }

        // add leading zeroes
        string memory leadingZeros = "";
        uint256 fractionalPartLength = bytes(fractionalPart.toString()).length;
        uint256 zerosToAdd = 5 > fractionalPartLength
            ? 5 - fractionalPartLength
            : 0;
        for (uint256 i = 0; i < zerosToAdd; i++) {
            leadingZeros = string(abi.encodePacked("0", leadingZeros));
        }
        return
            string(
                abi.encodePacked(
                    integerPart.toString(),
                    ".",
                    leadingZeros,
                    fractionalPart.toString()
                )
            );
    }

    function tickToString(int24 tick) private pure returns (string memory) {
        string memory sign = "";
        if (tick < 0) {
            tick = tick * -1;
            sign = "-";
        }
        return string(abi.encodePacked(sign, uint256(tick).toString()));
    }
}
