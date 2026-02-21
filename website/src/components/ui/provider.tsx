"use client";

import {
  ChakraProvider,
  createSystem,
  defaultConfig,
  ClientOnly,
  Skeleton,
} from "@chakra-ui/react";
import { ColorModeProvider, type ColorModeProviderProps } from "./color-mode";
import { COLORS } from "@/constants/common";

// Create a custom system with our theme
const system = createSystem(defaultConfig, {
  theme: {
    tokens: {
      colors: {
        brand: {
          primary: { value: COLORS.primary },
          secondary: { value: COLORS.secondary },
          accent: { value: COLORS.accent },
        },
      },
    },
  },
});

export function Provider(props: ColorModeProviderProps) {
  return (
    <ChakraProvider value={system}>
      <ClientOnly fallback={<Skeleton height="100vh" />}>
        <ColorModeProvider {...props} />
      </ClientOnly>
    </ChakraProvider>
  );
}
