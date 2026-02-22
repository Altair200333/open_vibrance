"use client";

import { VStack, Heading, Text } from "@chakra-ui/react";
import { Layout, ImageWithText } from "@/components";
import { APP_NAME } from "@/constants/common";

export default function Home() {
  return (
    <Layout>
      <VStack gap={8} align="center" justify="center" minHeight="80vh">
        <Heading as="h1" size="2xl" textAlign="center" color="gray.800" mb={4}>
          Welcome to {APP_NAME}
        </Heading>

        <ImageWithText
          imageSrc="https://via.placeholder.com/400x300/3182CE/ffffff?text=Open+Vibrance"
          imageAlt="Open Vibrance Logo"
          text="A beautiful and modern web application built with Next.js and Chakra UI"
          imageWidth="400px"
          imageHeight="300px"
          textSize="xl"
          spacing={6}
        />

        <Text
          fontSize="lg"
          color="gray.600"
          textAlign="center"
          maxWidth="600px"
          lineHeight="1.6"
        >
          This is a simple demonstration of a clean, responsive layout with an
          image centered on the page and descriptive text below it. The design
          uses Chakra UI components for consistent styling and great user
          experience.
        </Text>
      </VStack>
    </Layout>
  );
}
