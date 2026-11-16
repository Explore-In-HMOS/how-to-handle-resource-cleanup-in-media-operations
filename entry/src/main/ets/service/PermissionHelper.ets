import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { MICROPHONE_PERMISSION } from '../common/Constants';

export class PermissionHelper {
  static async ensureMicrophone(context: common.UIAbilityContext): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const tokenId = bundleInfo.appInfo.accessTokenId;
    const status = atManager.checkAccessTokenSync(tokenId, MICROPHONE_PERMISSION);
    if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    const result = await atManager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
    return result.authResults.length > 0 &&
      result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }
}
