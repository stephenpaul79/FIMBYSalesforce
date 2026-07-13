import {
  Nunito_400Regular,
  Nunito_600SemiBold,
  Nunito_700Bold,
  Nunito_800ExtraBold,
  Nunito_900Black,
  useFonts,
} from '@expo-google-fonts/nunito';
import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import 'react-native-reanimated';

import { useColorScheme } from '@/hooks/use-color-scheme';

// Hold the native (cream) splash until the brand font is ready so text never
// flashes in a fallback face before the pre-auth video takes over.
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const [fontsLoaded] = useFonts({
    Nunito_400Regular,
    Nunito_600SemiBold,
    Nunito_700Bold,
    Nunito_800ExtraBold,
    Nunito_900Black,
  });

  useEffect(() => {
    if (fontsLoaded) {
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded]);

  if (!fontsLoaded) {
    return null;
  }

  // Themed content background behind the Stack, matched to the app.json
  // splash colors so the ~1-frame gap between native splash lift and the
  // index.tsx's own paint doesn't flash a hardcoded color. Previously this
  // was locked to #67BBD2 (teal), which read as a bright flash between the
  // dark native splash and the dark splash video in dark mode. Duplicated
  // rather than imported from index.tsx to keep this layout module free of
  // heavy imports — if you change the app.json splash colors, mirror them
  // here (light) and in PREAUTH_COLORS.dark.bg / index.tsx (dark).
  const rootBg = colorScheme === 'dark' ? '#14100D' : '#F0EBE3';

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack
        screenOptions={{
          contentStyle: { backgroundColor: rootBg },
        }}
      >
        <Stack.Screen name="index" options={{ headerShown: false }} />
      </Stack>
    </ThemeProvider>
  );
}
