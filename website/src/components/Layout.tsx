"use client";

import { Box, Container } from "@chakra-ui/react";
import { CONTAINER_MAX_WIDTH } from "@/constants/common";

interface LayoutProps {
  children: React.ReactNode;
  maxWidth?: string;
  padding?: number;
  minHeight?: string;
}

export const Layout: React.FC<LayoutProps> = ({
  children,
  maxWidth = CONTAINER_MAX_WIDTH,
  padding = 8,
  minHeight = "100vh",
}) => {
  return (
    <Box minHeight={minHeight} bg="gray.50">
      <Container maxWidth={maxWidth} padding={padding} centerContent>
        {children}
      </Container>
    </Box>
  );
};
