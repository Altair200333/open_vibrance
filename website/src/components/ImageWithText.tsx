"use client";

import { Image, Text, VStack } from "@chakra-ui/react";
import { DEFAULT_IMAGE_ALT } from "@/constants/common";

interface ImageWithTextProps {
  imageSrc: string;
  imageAlt?: string;
  text: string;
  imageWidth?: string | number;
  imageHeight?: string | number;
  textSize?: string;
  spacing?: number;
}

export const ImageWithText: React.FC<ImageWithTextProps> = ({
  imageSrc,
  imageAlt = DEFAULT_IMAGE_ALT,
  text,
  imageWidth = "300px",
  imageHeight = "300px",
  textSize = "lg",
  spacing = 4,
}) => {
  return (
    <VStack gap={spacing} align="center">
      <Image
        src={imageSrc}
        alt={imageAlt}
        width={imageWidth}
        height={imageHeight}
        objectFit="cover"
        borderRadius="md"
        shadow="md"
      />
      <Text fontSize={textSize} textAlign="center" color="gray.700">
        {text}
      </Text>
    </VStack>
  );
};
