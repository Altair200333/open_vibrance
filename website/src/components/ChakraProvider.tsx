"use client";

import {
  ChakraProvider as ChakraUIProvider,
  extendTheme,
} from "@chakra-ui/react";
import { COLORS } from "@/constants/common";

// Extend the default theme with custom colors
const theme = extendTheme({
  colors: {
    brand: {
      primary: COLORS.primary,
      secondary: COLORS.secondary,
      accent: COLORS.accent,
    },
  },
  styles: {
    global: {
      body: {
        bg: "gray.50",
      },
    },
  },
});

interface ChakraProviderProps {
  children: React.ReactNode;
}

export const ChakraProvider: React.FC<ChakraProviderProps> = ({ children }) => {
  return <ChakraUIProvider theme={theme}>{children}</ChakraUIProvider>;
};
